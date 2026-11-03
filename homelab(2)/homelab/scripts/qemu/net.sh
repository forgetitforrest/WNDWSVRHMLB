#!/usr/bin/env bash
# net.sh - create or remove the lab network on the Linux host.
#
#   sudo ./net.sh up        create bridges, one tap per VM, enable routing and NAT
#   sudo ./net.sh down      remove taps, bridges, and the NAT rules
#   ./net.sh status         show what exists
#
# The host acts as the router between lab VLANs (bridges) and the internet.
# Set DRY_RUN=1 to print the commands instead of running them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${LAB_CONF:-$SCRIPT_DIR/lab.conf}"
[[ -f "$CONF" ]] || { echo "error: missing config $CONF" >&2; exit 1; }
# shellcheck source=lab.conf
source "$CONF"

DRY_RUN="${DRY_RUN:-0}"
OWNER="${LAB_USER:-${SUDO_USER:-root}}"     # user who will run QEMU and therefore owns the tap devices
NFT_TABLE="lab_nat"

log() { echo "[net] $*"; }
die() { echo "error: $*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == "1" ]]; then printf '%q ' "$@"; echo; else "$@"; fi; }

need_root() { [[ "$DRY_RUN" == "1" || $EUID -eq 0 ]] || die "run with sudo"; }

link_exists() { ip link show "$1" >/dev/null 2>&1; }

detect_uplink() {
    if [[ -n "${UPLINK:-}" ]]; then echo "$UPLINK"; return; fi
    ip route show default | awk '/default/ {print $5; exit}'
}

up() {
    need_root
    local br ip_cidr entry name bridge tap uplink

    for br in "${!BRIDGES[@]}"; do
        ip_cidr="${BRIDGES[$br]}"
        if link_exists "$br"; then
            log "bridge $br already exists"
        else
            log "creating bridge $br ($ip_cidr)"
            run ip link add name "$br" type bridge
            run ip addr add "$ip_cidr" dev "$br"
        fi
        run ip link set "$br" up
    done

    for entry in "${VMS[@]}"; do
        IFS='|' read -r name _ _ bridge _ <<< "$entry"
        tap="tap-$name"
        if link_exists "$tap"; then
            log "$tap already exists"
        else
            log "creating $tap on $bridge (owner: $OWNER)"
            run ip tuntap add dev "$tap" mode tap user "$OWNER"
        fi
        run ip link set "$tap" master "$bridge"
        run ip link set "$tap" up
    done

    run sysctl -qw net.ipv4.ip_forward=1

    uplink="$(detect_uplink)"
    [[ -n "$uplink" ]] || die "could not detect the uplink interface; set UPLINK in lab.conf"
    log "NAT $LAB_SUPERNET out through $uplink"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "nft add table ip $NFT_TABLE (masquerade $LAB_SUPERNET -> $uplink)"
    else
        nft delete table ip "$NFT_TABLE" 2>/dev/null || true
        nft -f - <<NFT
table ip $NFT_TABLE {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr $LAB_SUPERNET oifname "$uplink" masquerade
    }
}
NFT
    fi
    log "done. If clients on a routed VLAN need DHCP, see docs/qemu/networking.md (DHCP relay)."
}

down() {
    need_root
    local entry name br
    for entry in "${VMS[@]}"; do
        IFS='|' read -r name _ <<< "$entry"
        if link_exists "tap-$name"; then run ip link delete "tap-$name"; fi
    done
    for br in "${!BRIDGES[@]}"; do
        if link_exists "$br"; then run ip link delete "$br" type bridge; fi
    done
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "nft delete table ip $NFT_TABLE"
    else
        nft delete table ip "$NFT_TABLE" 2>/dev/null || true
    fi
    log "lab network removed"
}

status() {
    local br entry name
    for br in "${!BRIDGES[@]}"; do
        printf 'bridge %-12s %s\n' "$br" "$(link_exists "$br" && ip -brief addr show "$br" | awk '{print $1, $3}' || echo missing)"
    done
    for entry in "${VMS[@]}"; do
        IFS='|' read -r name _ <<< "$entry"
        printf 'tap    %-12s %s\n' "tap-$name" "$(link_exists "tap-$name" && echo present || echo missing)"
    done
    printf 'ip_forward = %s\n' "$(cat /proc/sys/net/ipv4/ip_forward)"
}

case "${1:-}" in
    up) up ;;
    down) down ;;
    status) status ;;
    *) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
