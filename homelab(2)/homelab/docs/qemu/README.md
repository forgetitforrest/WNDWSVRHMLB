# Running the Lab on QEMU/KVM

This section explains how to run the same Windows Server lab (two domain controllers, a file server, a test client) on **QEMU/KVM on a Linux host** instead of Hyper-V. The Windows side, including Active Directory, DNS, DHCP, Group Policy, and file services, is identical. Only the virtualization layer, the networking, and the VM lifecycle change.

| | |
|---|---|
| **Hypervisor** | QEMU with KVM acceleration, driven by the scripts in [`scripts/qemu/`](../../scripts/qemu/) |
| **Host OS** | x86-64 Linux (Debian/Ubuntu or Fedora commands are given) |
| **Guest OS** | Windows Server 2022 (evaluation ISO is fine), Windows 11 optional |
| **Last reviewed** | 2026-11-03 |

> **Status:** The scripts pass syntax checks and dry runs (`DRY_RUN=1`), but have **not** been tested against a real KVM host by the author of this template. Expect to adjust paths (UEFI firmware, interface names) and log what you changed in the [CHANGELOG](../../CHANGELOG.md).

## Which host?

| Host | Works? | Notes |
|---|---|---|
| **x86-64 Linux with KVM** | Yes, this guide | Fast, hardware-accelerated, supports bridged networking |
| **Linux VM (nested)** | Yes, slower | Enable nested virtualization on the outer hypervisor |
| **Windows host with QEMU** | Possible | Uses the WHPX accelerator, but bridging and tap networking work very differently. These scripts do not apply. If you have a Windows host, Hyper-V is the simpler choice. |
| **Apple Silicon Mac** | Not practical | Windows Server is x86-64. Emulating it on ARM is very slow. |

## Hyper-V concepts mapped to QEMU

| Hyper-V | QEMU/KVM (this lab) |
|---|---|
| Hyper-V host `HV01` | Linux host, see [host-setup.md](host-setup.md) |
| External vSwitch + VLAN tag | Linux bridge per VLAN + one tap per VM, see [networking.md](networking.md) |
| `.vhdx` | `.qcow2` (sparse, supports snapshots and backing files) |
| Generation 2 VM | `q35` machine with UEFI (OVMF) |
| Integration Services | virtio drivers + QEMU Guest Agent |
| Hyper-V Manager console | VNC on `127.0.0.1:590N` |
| Checkpoints | `qemu-img` internal snapshots (VM stopped), see [operations.md](operations.md) |
| VM Generation ID | `vmgenid` device with a fixed GUID per DC |
| Automatic start action | `lab.sh start all`, optionally via systemd |
| Template VHDX + copy | Sysprepped qcow2 as a read-only **backing file** |
| Router / firewall with DHCP relay | The Linux host (routing + NAT + optional DHCP relay) |

## What stays the same

These docs apply unchanged: [Active Directory](../services/active-directory.md), [DNS and DHCP](../services/dns-dhcp.md), [Group Policy](../services/group-policy.md), [FILE01](../servers/file01.md), [DC01](../servers/dc01.md), [DC02](../servers/dc02.md), [Add a new user](../runbooks/add-new-user.md), the IP plan and VLAN design in [topology.md](../network/topology.md). The in-guest Windows Server Backup setup in [backup.md](../services/backup.md) is also unchanged.

What is replaced is covered in [operations.md](operations.md#hyper-v-runbooks-and-their-qemu-equivalents).

## Quick start

1. **Prepare the host.** Install packages, check KVM, download the ISOs: [host-setup.md](host-setup.md).
2. **Configure.** Edit [`scripts/qemu/lab.conf`](../../scripts/qemu/lab.conf): firmware paths, bridge addresses, VM list.
3. **Create the network and disks.**
   ```bash
   cd scripts/qemu
   sudo ./net.sh up
   ./lab.sh init
   ```
4. **Install Windows** on DC01 (and the others): [vms.md](vms.md#install-windows-server).
   ```bash
   ./lab.sh install dc01      # then connect a VNC client to 127.0.0.1:5901
   ```
5. **Build the lab** in order (DC01, DC02, FILE01, client): [vms.md](vms.md#build-the-lab-in-order).
6. **Run it day to day:**
   ```bash
   ./lab.sh start all
   ./lab.sh status
   ./lab.sh stop all
   ```

## Documents in this section

- [host-setup.md](host-setup.md): packages, KVM, directories, ISOs, firmware
- [networking.md](networking.md): bridges, taps, routing, NAT, DHCP relay, optional firewall
- [vms.md](vms.md): VM definitions, Windows install with virtio, building the domain, templates
- [operations.md](operations.md): start/stop, boot automation, snapshots, backups, patching
- [troubleshooting.md](troubleshooting.md): symptoms and fixes
