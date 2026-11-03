# HV01: Hyper-V Host

> Running the lab on QEMU/KVM instead? Use [docs/qemu](../qemu/README.md) and keep this page only if you also have a Hyper-V host.

| | |
|---|---|
| **Role** | Hyper-V host for all lab VMs |
| **OS** | Windows Server 2022 Datacenter *(example)* |
| **Management IP** | 10.0.10.10 (VLAN 10) |
| **Domain joined** | Yes (`lab.example.com`) |
| **Hardware** | `<CPU>`, `<RAM>` GB RAM, `<OS DISK>`, `<VM DISK>` |
| **Installed roles** | Hyper-V, Windows Server Backup |
| **Backup** | Nightly to NAS01 ([backup.md](../services/backup.md)) |
| **Last reviewed** | 2026-11-03 |

## Storage layout

| Drive | Purpose | Notes |
|---|---|---|
| C: | OS | Management OS only, nothing else installed |
| D: | VM storage | `D:\Hyper-V\VMs` (configs), `D:\Hyper-V\VHDX` (disks) |
| D: | Templates | `D:\Hyper-V\Templates` (sysprepped golden images, read-only) |
| D: | ISOs | `D:\ISO` |

Default paths set with:

```powershell
Set-VMHost -VirtualMachinePath 'D:\Hyper-V\VMs' -VirtualHardDiskPath 'D:\Hyper-V\VHDX'
```

## Virtual switches

| Name | Type | Bound to | Share with management OS |
|---|---|---|---|
| vSwitch-External | External | NIC 1 | Yes (management VLAN 10 tagged) |

VM network adapters are assigned a VLAN with:

```powershell
Set-VMNetworkAdapterVlan -VMName 'DC01' -Access -VlanId 20
```

## Virtual machines

| VM | Gen | vCPU | RAM | Disk | VLAN | Autostart | Notes |
|---|---|---|---|---|---|---|---|
| DC01 | 2 | 2 | 4 GB static | 60 GB | 20 | Yes, delay 0 s | Start first |
| DC02 | 2 | 2 | 4 GB static | 60 GB | 20 | Yes, delay 30 s | |
| FILE01 | 2 | 2 | 4 GB dynamic (2-8 GB) | 60 GB OS + 500 GB data | 20 | Yes, delay 60 s | |
| WIN11-01 | 2 | 2 | 4 GB dynamic | 80 GB | 30 | No | Test client |

## Settings and policies

- **Checkpoints:** Use **Production checkpoints** only. **Never** use standard checkpoints on domain controllers, since reverting them causes USN rollback and AD replication corruption. Delete checkpoints after the change is verified.
- **Dynamic Memory:** Off for domain controllers, on for file and test VMs.
- **Integration services:** Time synchronisation is **disabled on DC01** (the PDC emulator, which syncs from NTP instead) and left at the default elsewhere.
- **Automatic start/stop:** VMs start automatically; stop action is *Shut down the guest OS*.
- **Power:** Host on UPS. See `<UPS MODEL>` for runtime and shutdown settings.

## Common commands

```powershell
Get-VM | Select Name, State, CPUUsage, MemoryAssigned, Uptime
Get-VMCheckpoint -VMName * | Select VMName, Name, CreationTime
Get-VMHost | Select Name, VirtualMachinePath, VirtualHardDiskPath
```

## Known issues / notes

- *(none yet)*
