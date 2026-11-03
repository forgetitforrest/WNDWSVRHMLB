#!/usr/bin/env bash
# lab.sh - create, start, stop, and inspect the QEMU/KVM version of the homelab.
#
#   ./lab.sh init                         create the qcow2 disks defined in lab.conf
#   ./lab.sh install <vm>                 boot a VM with the Windows + virtio ISOs attached
#   ./lab.sh start [vm ...|all]           start VMs (all = VMs with the 'autostart' flag, in order)
#   ./lab.sh stop  [vm ...|all]           graceful ACPI shutdown (all = reverse order)
#   ./lab.sh kill <vm>                    hard stop (like pulling the power; last resort)
#   ./lab.sh status                       show VM and network state
#   ./lab.sh console <vm>                 print how to connect to the VM's screen
#   ./lab.sh snap <create|list|apply|delete> <vm> [name]   internal snapshots (VM must be stopped)
#
# Set DRY_RUN=1 to print the commands instead of running them.
# Run as a normal user in the 'kvm' group. Networking (bridges/taps) is set up by net.sh, as root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${LAB_CONF:-$SCRIPT_DIR/lab.conf}"
[[ -f "$CONF" ]] || { echo "error: missing config $CONF" >&2; exit 1; }
# shellcheck source=lab.conf
source "$CONF"

DRY_RUN="${DRY_RUN:-0}"

log() { echo "[lab] $*"; }
die() { echo "error: $*" >&2; exit 1; }

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '%q ' "$@"; echo
    else
        "$@"
    fi
}

# ---------- VM table helpers ----------
vm_names() { local e; for e in "${VMS[@]}"; do echo "${e%%|*}"; done; }

load_vm() {  # sets VM_* variables for the named VM
    local line="" e
    for e in "${VMS[@]}"; do
        [[ "${e%%|*}" == "$1" ]] && line="$e"
    done
    [[ -n "$line" ]] || die "unknown VM '$1' (known: $(vm_names | tr '\n' ' '))"
    IFS='|' read -r VM_NAME VM_VCPU VM_MEM VM_BRIDGE VM_MAC VM_VNC VM_FLAGS VM_GENID <<< "$line"
    VM_DISK="$DISK_DIR/$VM_NAME.qcow2"
    VM_PID="$RUN_DIR/$VM_NAME.pid"
    VM_QMP="$RUN_DIR/$VM_NAME.qmp"
    VM_TAP="tap-$VM_NAME"
}

has_flag() { [[ ",${VM_FLAGS:-}," == *",$1,"* ]]; }

is_running() { [[ -f "$VM_PID" ]] && kill -0 "$(cat "$VM_PID")" 2>/dev/null; }

# ---------- firmware ----------
set_firmware() {
    FW_CODE="$OVMF_CODE"; FW_VARS_TPL="$OVMF_VARS_TEMPLATE"; MACHINE="q35,accel=kvm"
    if has_flag secboot; then
        FW_CODE="$OVMF_CODE_SECBOOT"; FW_VARS_TPL="$OVMF_VARS_SECBOOT_TEMPLATE"; MACHINE="q35,accel=kvm,smm=on"
    fi
    FW_VARS="$RUN_DIR/$VM_NAME-OVMF_VARS.fd"
}

start_tpm() {
    local dir="$RUN_DIR/$VM_NAME-tpm"
    run mkdir -p "$dir"
    run swtpm socket --tpmstate "dir=$dir" --ctrl "type=unixio,path=$RUN_DIR/$VM_NAME.swtpm" \
        --tpm2 --daemon --terminate
}

# ---------- QEMU command line ----------
build_args() {  # $1 = run | install
    local mode="$1" extra suffix
    set_firmware
    QARGS=(
        "$QEMU_BIN"
        -name "guest=$VM_NAME,process=qemu-$VM_NAME"
        -machine "$MACHINE"
        -cpu "host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time"
        -smp "$VM_VCPU" -m "$VM_MEM"
        -rtc base=localtime
        -drive "if=pflash,format=raw,readonly=on,file=$FW_CODE"
        -drive "if=pflash,format=raw,file=$FW_VARS"
        -drive "file=$VM_DISK,if=none,id=disk0,format=qcow2,cache=none,aio=native,discard=unmap"
        -device virtio-blk-pci,drive=disk0
    )

    extra="${EXTRA_DISKS[$VM_NAME]:-}"
    if [[ -n "$extra" ]]; then
        suffix="${extra%%:*}"
        QARGS+=(
            -drive "file=$DISK_DIR/$VM_NAME-$suffix.qcow2,if=none,id=disk1,format=qcow2,cache=none,aio=native,discard=unmap"
            -device virtio-blk-pci,drive=disk1
        )
    fi

    QARGS+=(
        -netdev "tap,id=net0,ifname=$VM_TAP,script=no,downscript=no"
        -device "virtio-net-pci,netdev=net0,mac=$VM_MAC"
        -device qemu-xhci -device usb-tablet
        -device VGA
        -display none -vnc "127.0.0.1:$VM_VNC"
        # QMP socket for graceful shutdown, guest-agent socket for later use
        -qmp "unix:$VM_QMP,server=on,wait=off"
        -chardev "socket,id=qga0,path=$RUN_DIR/$VM_NAME.qga,server=on,wait=off"
        -device virtio-serial -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        -pidfile "$VM_PID" -daemonize
    )

    if [[ -n "${VM_GENID:-}" ]]; then
        QARGS+=(-device "vmgenid,guid=$VM_GENID,id=vmgenid0")
    fi
    if has_flag secboot; then
        QARGS+=(-global driver=cfi.pflash01,property=secure,value=on)
    fi
    if has_flag tpm; then
        QARGS+=(
            -chardev "socket,id=chrtpm,path=$RUN_DIR/$VM_NAME.swtpm"
            -tpmdev emulator,id=tpm0,chardev=chrtpm
            -device tpm-tis,tpmdev=tpm0
        )
    fi
    if [[ "$mode" == "install" ]]; then
        QARGS+=(
            -drive "file=$WIN_ISO,media=cdrom,readonly=on"
            -drive "file=$VIRTIO_ISO,media=cdrom,readonly=on"
        )
    fi
}

# ---------- commands ----------
cmd_init() {
    local n size extra suffix
    run mkdir -p "$DISK_DIR" "$ISO_DIR" "$RUN_DIR"
    for n in $(vm_names); do
        load_vm "$n"
        size="${DISK_SIZES[$n]:-60G}"
        if [[ -f "$VM_DISK" ]]; then
            log "$VM_DISK exists, skipping"
        else
            run qemu-img create -f qcow2 "$VM_DISK" "$size"
        fi
        extra="${EXTRA_DISKS[$n]:-}"
        if [[ -n "$extra" ]]; then
            suffix="${extra%%:*}"; size="${extra##*:}"
            if [[ -f "$DISK_DIR/$n-$suffix.qcow2" ]]; then
                log "$DISK_DIR/$n-$suffix.qcow2 exists, skipping"
            else
                run qemu-img create -f qcow2 "$DISK_DIR/$n-$suffix.qcow2" "$size"
            fi
        fi
    done
}

launch() {  # $1 = vm name, $2 = run | install
    load_vm "$1"
    if is_running; then log "$VM_NAME is already running"; return 0; fi
    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -f "$VM_DISK" ]] || die "missing disk $VM_DISK (run: $0 init)"
        ip link show "$VM_TAP" >/dev/null 2>&1 || die "network device $VM_TAP not found (run: sudo ./net.sh up)"
        if [[ "$2" == "install" ]]; then
            [[ -f "$WIN_ISO" ]] || die "missing $WIN_ISO"
            [[ -f "$VIRTIO_ISO" ]] || die "missing $VIRTIO_ISO"
        fi
    fi
    set_firmware
    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -f "$FW_CODE" ]] || die "UEFI firmware not found: $FW_CODE (fix OVMF_CODE in lab.conf)"
        [[ -f "$FW_VARS" || -f "$FW_VARS_TPL" ]] || die "UEFI variable template not found: $FW_VARS_TPL (fix lab.conf)"
    fi
    [[ -f "$FW_VARS" ]] || run cp "$FW_VARS_TPL" "$FW_VARS"
    if has_flag tpm; then start_tpm; fi
    build_args "$2"
    log "starting $VM_NAME ($2 mode), screen at 127.0.0.1:$((5900 + VM_VNC))"
    run "${QARGS[@]}"
}

cmd_install() { [[ $# -eq 1 ]] || die "usage: $0 install <vm>"; launch "$1" install; }

cmd_start() {
    local targets=() n first=1
    if [[ $# -eq 0 || "$1" == "all" ]]; then
        for n in $(vm_names); do
            load_vm "$n"
            if has_flag autostart; then targets+=("$n"); fi
        done
    else
        targets=("$@")
    fi
    for n in "${targets[@]}"; do
        if [[ $first -eq 0 && ${#targets[@]} -gt 1 && "$DRY_RUN" != "1" ]]; then sleep "$START_DELAY"; fi
        launch "$n" run
        first=0
    done
}

stop_one() {
    local waited=0
    load_vm "$1"
    if ! is_running; then log "$VM_NAME is not running"; return 0; fi
    log "sending ACPI shutdown to $VM_NAME"
    printf '{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n' |
        run socat -t 1 - "UNIX-CONNECT:$VM_QMP" > /dev/null
    while is_running; do
        if (( waited >= STOP_TIMEOUT )); then
            log "$VM_NAME did not stop within ${STOP_TIMEOUT}s (check the screen, or: $0 kill $VM_NAME)"
            return 1
        fi
        sleep 2; waited=$((waited + 2))
    done
    log "$VM_NAME stopped"
}

cmd_stop() {
    local names=() targets=() i
    if [[ $# -eq 0 || "$1" == "all" ]]; then
        mapfile -t names < <(vm_names)
        for (( i=${#names[@]}-1; i>=0; i-- )); do targets+=("${names[i]}"); done   # reverse order
    else
        targets=("$@")
    fi
    for i in "${targets[@]}"; do stop_one "$i" || true; done
}

cmd_kill() {
    [[ $# -eq 1 ]] || die "usage: $0 kill <vm>"
    load_vm "$1"
    if ! is_running; then log "$VM_NAME is not running"; return 0; fi
    log "hard-stopping $VM_NAME (equivalent to pulling the power)"
    run kill "$(cat "$VM_PID")"
}

cmd_status() {
    local n state
    printf '%-10s %-9s %-12s %-12s %s\n' VM STATE BRIDGE SCREEN TAP
    for n in $(vm_names); do
        load_vm "$n"
        if is_running; then state=running; else state=stopped; fi
        printf '%-10s %-9s %-12s %-12s %s\n' "$VM_NAME" "$state" "$VM_BRIDGE" "127.0.0.1:$((5900 + VM_VNC))" \
            "$(ip link show "$VM_TAP" >/dev/null 2>&1 && echo up || echo missing)"
    done
    echo
    for n in "${!BRIDGES[@]}"; do
        printf 'bridge %-12s %s\n' "$n" "$(ip link show "$n" >/dev/null 2>&1 && echo present || echo missing)"
    done
}

cmd_console() {
    [[ $# -eq 1 ]] || die "usage: $0 console <vm>"
    load_vm "$1"
    echo "VNC:    127.0.0.1:$((5900 + VM_VNC))"
    echo "Local:  remote-viewer vnc://127.0.0.1:$((5900 + VM_VNC))   (or any VNC client)"
    echo "Remote: ssh -L $((5900 + VM_VNC)):127.0.0.1:$((5900 + VM_VNC)) <lab-host>   then connect to localhost:$((5900 + VM_VNC))"
}

cmd_snap() {
    [[ $# -ge 2 ]] || die "usage: $0 snap <create|list|apply|delete> <vm> [name]"
    local action="$1" vm="$2" name="${3:-}"
    load_vm "$vm"
    if is_running; then die "$VM_NAME is running. Shut it down first ($0 stop $VM_NAME)."; fi
    if has_flag dc && [[ "$action" != "list" && "${ALLOW_DC_SNAPSHOT:-0}" != "1" ]]; then
        die "$VM_NAME is a domain controller. Reverting a DC snapshot can cause USN rollback. See docs/qemu/operations.md. Set ALLOW_DC_SNAPSHOT=1 to override."
    fi
    case "$action" in
        create) [[ -n "$name" ]] || die "snapshot name required"; run qemu-img snapshot -c "$name" "$VM_DISK" ;;
        list)   run qemu-img snapshot -l "$VM_DISK" ;;
        apply)  [[ -n "$name" ]] || die "snapshot name required"; run qemu-img snapshot -a "$name" "$VM_DISK"
                [[ -n "${VM_GENID:-}" ]] && log "reminder: this is a DC, generate a new VM-Generation-ID in lab.conf before starting it" || true ;;
        delete) [[ -n "$name" ]] || die "snapshot name required"; run qemu-img snapshot -d "$name" "$VM_DISK" ;;
        *) die "unknown snap action '$action'" ;;
    esac
}

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
    local cmd="${1:-}"; shift || true
    case "$cmd" in
        init)    cmd_init "$@" ;;
        install) cmd_install "$@" ;;
        start)   cmd_start "$@" ;;
        stop)    cmd_stop "$@" ;;
        kill)    cmd_kill "$@" ;;
        status)  cmd_status "$@" ;;
        console) cmd_console "$@" ;;
        snap)    cmd_snap "$@" ;;
        ""|-h|--help|help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"
