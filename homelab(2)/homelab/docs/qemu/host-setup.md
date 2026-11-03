# QEMU Host Setup

## Host record

| | |
|---|---|
| **Hostname** | `<LINUX HOST>` |
| **OS** | `<DISTRO + VERSION>` (e.g. Ubuntu 24.04 LTS) |
| **CPU** | `<CPU>`, must support virtualization (Intel VT-x or AMD-V) |
| **RAM** | `<RAM>` GB (lab VMs below use 16 GB, leave at least 4 GB for the host) |
| **Storage** | `<SSD>` for `/srv/lab` (disks, ISOs, state) |
| **Management IP** | `<HOST IP>` (VLAN 10 / home LAN) |
| **Last reviewed** | 2026-11-03 |

## Sizing

| VM | vCPU | RAM | Disk |
|---|---|---|---|
| DC01 | 2 | 4 GB | 60 GB |
| DC02 | 2 | 4 GB | 60 GB |
| FILE01 | 2 | 4 GB | 60 GB + 500 GB data |
| WIN11-01 (optional) | 2 | 4 GB | 80 GB |

qcow2 disks are sparse, so they only use the space the guest has actually written. RAM is not shared between running VMs, so size the host for the total.

## 1. Check virtualization support

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo     # > 0 means the CPU supports it (enable VT-x/AMD-V in BIOS/UEFI if 0)
ls -l /dev/kvm                          # should exist, group 'kvm'
```

If `/dev/kvm` is missing, enable virtualization in the firmware, or if the host is itself a VM, enable nested virtualization on the outer hypervisor.

## 2. Install packages

**Debian / Ubuntu**

```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils ovmf swtpm swtpm-tools socat nftables iproute2
```

**Fedora**

```bash
sudo dnf install qemu-kvm qemu-img edk2-ovmf swtpm swtpm-tools socat nftables iproute
```

| Package | Why |
|---|---|
| `qemu-system-x86`, `qemu-utils` | The hypervisor and `qemu-img` |
| `ovmf` / `edk2-ovmf` | UEFI firmware (Generation 2-style boot) |
| `swtpm`, `swtpm-tools` | Software TPM, only needed for a Windows 11 client |
| `socat` | Talks to the QMP socket for graceful shutdown |
| `nftables` | NAT for the lab network |

## 3. Let your user run QEMU

```bash
sudo usermod -aG kvm "$USER"
# log out and back in, then check:
id -nG | tr ' ' '\n' | grep -x kvm
```

Networking changes need root (`sudo ./net.sh up`), but the VMs themselves run as your normal user.

## 4. Create the directory layout

```bash
sudo mkdir -p /srv/lab/{disks,iso,run}
sudo chown -R "$USER":kvm /srv/lab
```

| Directory | Contents |
|---|---|
| `/srv/lab/disks` | `.qcow2` disks |
| `/srv/lab/iso` | Installation media |
| `/srv/lab/run` | PID files, QMP sockets, per-VM UEFI variables, TPM state |

Use a different location by setting `LAB_DIR` (in your shell or `lab.conf`).

## 5. Download installation media

Put these in `/srv/lab/iso/`:

| File | Source |
|---|---|
| `ws2022-eval.iso` | Windows Server 2022 evaluation ISO from the Microsoft Evaluation Center (180-day trial). Pick **ISO**, 64-bit. |
| `virtio-win.iso` | `wget -O /srv/lab/iso/virtio-win.iso https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso` |
| `win11.iso` (optional) | Windows 11 ISO from Microsoft |

Use the **stable** virtio-win ISO. The "latest" one can contain pre-release drivers. If you hit a driver problem, older versions are in the project's archive directory.

Update `WIN_ISO` and `VIRTIO_ISO` in `lab.conf` if you name the files differently.

## 6. Find the UEFI firmware files

```bash
ls /usr/share/OVMF /usr/share/edk2/ovmf 2>/dev/null
```

| Distro | Typical `OVMF_CODE` | Typical `OVMF_VARS` template |
|---|---|---|
| Ubuntu 22.04+ | `/usr/share/OVMF/OVMF_CODE_4M.fd` | `/usr/share/OVMF/OVMF_VARS_4M.fd` |
| Fedora | `/usr/share/edk2/ovmf/OVMF_CODE.fd` | `/usr/share/edk2/ovmf/OVMF_VARS.fd` |

Set `OVMF_CODE` and `OVMF_VARS_TEMPLATE` in `lab.conf` to match. For a Windows 11 client you also need the Secure Boot variants (`..._CODE_4M.secboot.fd` and `..._VARS_4M.ms.fd` on Ubuntu). File names vary by distro version, so check the listing.

Each VM gets its **own copy** of the variable store in `/srv/lab/run/<vm>-OVMF_VARS.fd`. The firmware code file is shared and read-only.

## 7. Verify

```bash
qemu-system-x86_64 --version
qemu-system-x86_64 -accel help          # should list kvm
cd scripts/qemu && ./lab.sh status       # table of VMs, all 'stopped' / 'missing' at this point
```

Next: [networking.md](networking.md).
