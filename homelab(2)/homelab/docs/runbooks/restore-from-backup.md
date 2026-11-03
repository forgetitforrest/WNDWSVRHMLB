# Runbook: Restore from Backup

## When to use

- Files or folders were deleted, overwritten, or encrypted.
- A VM is corrupted or lost.
- Active Directory objects were deleted, or AD is damaged.

**Choose the lightest option that fixes the problem.** Prefer Previous Versions or the AD Recycle Bin over a full restore.

## Prerequisites

- Admin access using your `adm-*` account.
- Network access to NAS01 (`\\NAS01\backups`) and the backup account credential (from the password manager).
- The **DSRM password** for any domain controller restore (from the password manager).
- Know what you are restoring and **to when**.

## 1. A file or folder on FILE01

### Try Previous Versions first

On a client: right-click the folder, **Properties > Previous Versions**, pick a snapshot and **Restore** or **Open**.

### Otherwise restore from WSB (on FILE01)

```powershell
# List available backups
wbadmin get versions -backupTarget:\\NAS01\backups\FILE01

# Restore a folder to a scratch location (safer than overwriting)
wbadmin start recovery -version:11/02/2026-03:00 -itemType:File `
    -items:E:\Shares\Dept\Finance -recursive `
    -recoveryTarget:E:\Restore -backupTarget:\\NAS01\backups\FILE01
```

Check the restored data, then copy it back into place. Version format is `MM/DD/YYYY-HH:MM`.

## 2. A virtual machine

1. On HV01, open **Windows Server Backup**, choose **Recover > This server > pick the date > Hyper-V**.
2. Select the VM, and restore to the original location (VM must be off or removed) or to an alternate folder.
3. If restored to an alternate folder, import it: `Import-VM -Path '<path>\...\<GUID>.vmcx' -Copy -GenerateNewId`. Use `-GenerateNewId` only if the original still exists.
4. Start the VM, check the network adapter VLAN, and run `Get-LabHealth.ps1`.

**Domain controller VMs:** if the other DC is healthy, do **not** restore a DC VM from backup. Delete the broken one and rebuild/re-promote it, which is faster and safer. See [dc02.md](../servers/dc02.md).

## 3. Deleted Active Directory objects

Use the Recycle Bin (no backup needed):

```powershell
Get-ADObject -Filter 'isDeleted -eq $true -and Name -like "*jsmith*"' -IncludeDeletedObjects |
    Restore-ADObject
```

Restored objects return with their group memberships and attributes.

## 4. Active Directory damage (last resort)

Use only if AD is corrupted on **all** DCs, or objects were deleted beyond Recycle Bin recovery.

**Non-authoritative restore** (bring one DC back, then it catches up from partners):

1. Boot the DC into Directory Services Restore Mode: `bcdedit /set safeboot dsrepair`, then reboot, and log on with the DSRM password.
2. Restore System State:
   ```powershell
   wbadmin get versions -backupTarget:\\NAS01\backups\DC01
   wbadmin start systemstaterecovery -version:11/02/2026-02:30 -backupTarget:\\NAS01\backups\DC01 -quiet
   ```
3. Reboot. Remove safe-boot: `bcdedit /deletevalue safeboot` (if it still applies).
4. Verify: `repadmin /replsummary`, `dcdiag /q`.

**Authoritative restore** (force the restored data to overwrite other DCs, only for restoring deleted/changed objects):

- After step 2 and **before** the reboot:
  ```
  ntdsutil
  activate instance ntds
  authoritative restore
  restore subtree "OU=Staff,OU=Users,OU=_Lab,DC=lab,DC=example,DC=com"
  quit
  quit
  ```
- Then reboot normally and let replication push the restored objects out.

> If the network share is not reachable from DSRM, copy the backup to a local or USB disk first and point `-backupTarget` at that.

## Verify

- [ ] Data opens and permissions are correct (`icacls` on the folder, if relevant).
- [ ] `Get-LabHealth.ps1` is clean.
- [ ] A new backup runs successfully the next night.

## After the restore

- [ ] Add a dated entry to [CHANGELOG.md](../../CHANGELOG.md): what failed, what was restored, from which backup.
- [ ] Add a row to the restore-test table in [backup.md](../services/backup.md).
- [ ] Note the root cause and how to prevent it.

## Escalation

If a restore fails or the backup is unreadable, **stop and do not overwrite the damaged data further.** Copy it aside first, then check the offsite copy.
