# Backup

| | |
|---|---|
| **Tool** | Windows Server Backup (WSB) |
| **Target** | NAS01 (`\\NAS01\backups`, VLAN 10) |
| **Schedule** | Nightly at 02:00 |
| **Restore tested** | `<DATE>`, repeat quarterly |
| **Last reviewed** | 2026-11-03 |

## What gets backed up

| Host | What | Frequency | Retention | Target path |
|---|---|---|---|---|
| HV01 | Host system state + all VMs | Nightly 02:00 | See note below | `\\NAS01\backups\HV01` |
| DC01 | System State + critical volumes | Nightly 02:30 | See note below | `\\NAS01\backups\DC01` |
| DC02 | System State | Nightly 02:30 | See note below | `\\NAS01\backups\DC02` |
| FILE01 | Data volume `E:` + System State | Nightly 03:00 | See note below | `\\NAS01\backups\FILE01` |

> **Retention caveat:** when WSB backs up to a **network share**, it keeps **only the most recent backup** and overwrites it each run. To keep multiple versions, back up to a dedicated local or iSCSI disk or VHD, or have the NAS snapshot the share on a schedule (e.g. daily, keep 14). Whichever you choose, record it here.

## 3-2-1 goal

| Copy | Where | Status |
|---|---|---|
| 1. Live data | VMs on HV01 | Done |
| 2. Local backup | NAS01 (different device, different VLAN) | Done |
| 3. Offsite / offline copy | `<CLOUD / EXTERNAL DISK>` | `<TODO>` |

A backup on the same host as the data does not protect against host failure, theft, fire, or ransomware that reaches the share. Use the offsite copy.

## Configure WSB (example for FILE01)

```powershell
Install-WindowsFeature Windows-Server-Backup

$policy = New-WBPolicy
Add-WBVolume -Policy $policy -Volume (Get-WBVolume -VolumePath 'E:')
Add-WBSystemState -Policy $policy
$target = New-WBBackupTarget -NetworkPath '\\NAS01\backups\FILE01' -Credential (Get-Credential)
Add-WBBackupTarget -Policy $policy -Target $target
Set-WBSchedule -Policy $policy -Schedule ([datetime]'03:00')
Set-WBPolicy -Policy $policy
```

On HV01, add the VMs to the policy:

```powershell
Get-WBVirtualMachine | ForEach-Object { Add-WBVirtualMachine -Policy $policy -VirtualMachine $_ }
```

`Get-Credential` prompts for the NAS account. Do **not** put the password in a script or this repo. The backup account should have write access to its own folder only.

## Checking backups

```powershell
Get-WBSummary                # last backup time and result
Get-WBJob -Previous 1        # last job detail
wbadmin get versions         # available versions
```

Look at `Get-WBSummary` weekly, or add a check to `Get-LabHealth.ps1`.

## Restore testing

An untested backup is a hope, not a backup. Once a quarter, restore one of each into a scratch location and record the result:

| Date | Item restored | Method | Result | Time taken | Notes |
|---|---|---|---|---|---|
| `<DATE>` | A folder from FILE01 | `wbadmin` | | | |
| `<DATE>` | A VM from HV01 | WSB console | | | |
| `<DATE>` | DC System State (test VM only) | `wbadmin` / DSRM | | | |

Procedures: [Restore from backup](../runbooks/restore-from-backup.md).

## Known issues / notes

- *(none yet)*
