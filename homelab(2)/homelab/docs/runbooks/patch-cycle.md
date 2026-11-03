# Runbook: Monthly Patch Cycle

## When to use

Monthly, a week or so after Patch Tuesday (second Tuesday of the month), so any bad updates are caught by others first.

## Prerequisites

- A recent, successful backup of every host (`Get-WBSummary` on each).
- A maintenance window of about 2 hours. Tell anyone using the lab.
- Admin access using your `adm-*` account.
- Run `Get-LabHealth.ps1` and confirm the lab is **healthy before you start**. Never patch on top of an existing problem.

## Order of operations

Patch in this order so the lab stays up as long as possible:

1. DC02
2. DC01 (verify DC02 is healthy first)
3. FILE01 and any other member servers
4. Test clients
5. HV01 (last, since it takes every VM down)

## Procedure

### 1. Pre-checks

```powershell
.\scripts\powershell\Get-LabHealth.ps1
```

### 2. Optional safety net on each VM (from HV01)

```powershell
Set-VM -Name FILE01 -CheckpointType Production
Checkpoint-VM -Name FILE01 -SnapshotName "pre-patch-$(Get-Date -Format yyyy-MM-dd)"
```

> **Domain controllers:** do not use checkpoints as a rollback method. Reverting a DC to a checkpoint can cause USN rollback. Rely on backups for DCs.

### 3. Patch each server in order

Via `sconfig` (option 6) or Windows Update. If you use the PSWindowsUpdate module:

```powershell
Install-WindowsUpdate -AcceptAll -AutoReboot
```

After each server comes back, verify before moving on:

| Server | Check |
|---|---|
| DC02 / DC01 | `dcdiag /q`, `repadmin /replsummary`, `Get-DhcpServerv4Failover` |
| FILE01 | Browse `\\FILE01\Public$`, check `Get-SmbShare` |
| Clients | Log on, drive maps present, `gpresult /r` |

### 4. Patch HV01 last

```powershell
Get-VM | Where-Object State -eq 'Running' | Stop-VM            # graceful shutdown
# install updates on HV01 and reboot
# VMs autostart in order: DC01, DC02 (30 s), FILE01 (60 s)
```

### 5. Post-checks

```powershell
.\scripts\powershell\Get-LabHealth.ps1
```

- [ ] Delete pre-patch checkpoints once everything is verified.
- [ ] Re-run `Export-LabConfig.ps1` if anything changed, and commit.
- [ ] Add a line to [CHANGELOG.md](../../CHANGELOG.md): date, KB numbers or month, any issues.

## Rollback

| Situation | Action |
|---|---|
| Bad update on a member server | Uninstall via Settings or `wusa /uninstall /kb:<KB>`, or revert to the pre-patch checkpoint |
| Bad update on a DC | Uninstall the update. If AD is damaged, follow [Restore from backup](restore-from-backup.md). |
| Host will not boot | Boot from the last known good config or restore from backup |

## Escalation

If both DCs are unhealthy after patching, stop. Do not patch anything else, and start with [Restore from backup](restore-from-backup.md).
