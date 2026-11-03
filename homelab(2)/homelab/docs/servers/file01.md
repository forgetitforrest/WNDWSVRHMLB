# FILE01: File Server

| | |
|---|---|
| **Role** | SMB file server |
| **OS** | Windows Server 2022 Standard *(example)* |
| **IP** | 10.0.20.20 (VLAN 20), static |
| **Host** | VM on HV01 |
| **Specs** | 2 vCPU / 2-8 GB dynamic RAM / 60 GB OS disk + 500 GB data disk |
| **Installed roles** | File and Storage Services, File Server Resource Manager *(optional)* |
| **Backup** | Windows Server Backup, nightly data volume to NAS01 |
| **Last reviewed** | 2026-11-03 |

## Shares

| Share | Path | Purpose | Access (AGDLP) |
|---|---|---|---|
| `Public$` | `E:\Shares\Public` | Shared files for everyone | `DL-Public-Modify` (contains `GG-AllStaff`) |
| `Dept` | `E:\Shares\Dept\<Dept>` | Per-department folders | `DL-Dept-<Dept>-Modify` |
| `Home$` | `E:\Shares\Home\%username%` | Home drives | Owner only + `GG-Admins` |
| `IT$` | `E:\Shares\IT` | IT tools and installers | `DL-IT-Modify` (contains `GG-IT`) |

## Permissions model

- **Share permissions:** `Everyone: Full Control` on the share, with security handled by NTFS.
- **NTFS permissions:** assigned to **domain local** groups only. Never to individual users.
- Users are placed in **global** groups, and those are nested into the domain local groups.
- Remove inheritance only at the top of a share, and document any exception here.

## Features enabled

- **Shadow Copies (VSS)** on `E:` at 07:00 and 12:00 weekdays for Previous Versions.
- **Access-based enumeration** on `Dept` and `Home$`.
- **Quotas** *(optional)*: 5 GB per home folder via FSRM.

## Common commands

```powershell
Get-SmbShare | Where-Object { $_.Name -notlike '*$' -or $_.Name -in 'Home$','IT$','Public$' }
Get-SmbSession
Get-Volume -DriveLetter E | Select DriveLetter, SizeRemaining, Size
vssadmin list shadows /for=E:
```

## Known issues / notes

- *(none yet)*
