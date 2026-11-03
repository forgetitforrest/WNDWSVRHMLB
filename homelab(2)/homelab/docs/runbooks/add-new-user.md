# Runbook: Add (and Remove) a User

## When to use

Onboarding a new person to the domain, or offboarding someone who is leaving.

## Prerequisites

- Domain admin (or delegated user-management) rights, using your `adm-*` account.
- RSAT Active Directory tools, or run directly on a DC.
- The person's name, department, and which groups they need.

## Onboarding

### Option A: Script (preferred)

```powershell
.\scripts\powershell\New-LabUser.ps1 -GivenName 'Jane' -Surname 'Smith' -Department 'Finance' -Groups 'GG-AllStaff','GG-Finance'
```

The script:
- builds the username (`jsmith`, adding a number if taken)
- creates the account in `OU=Staff,OU=Users,OU=_Lab,...`
- sets a random temporary password and **requires a change at first logon**
- adds the groups
- prints the temporary password **once**, on screen only (it is never written to disk or this repo)

Give the password to the user through a channel separate from the username.

### Option B: Manual

1. Open **Active Directory Users and Computers** and go to `_Lab > Users > Staff`.
2. Right-click, **New > User**. Use the naming convention in [active-directory.md](../services/active-directory.md).
3. Set a strong temporary password and tick **User must change password at next logon**.
4. Open **Member Of** and add the global groups (`GG-*`) for their role. Never grant access directly.

### Verify

```powershell
Get-ADUser jsmith -Properties MemberOf, PasswordLastSet, Enabled | Select Name, Enabled, MemberOf
```

Have the user log on from a client and confirm their drive maps appear.

### Finish

- Add a line to [CHANGELOG.md](../../CHANGELOG.md) (usernames only, no passwords).

## Offboarding

1. **Disable** the account (do not delete yet):
   ```powershell
   Disable-ADAccount -Identity jsmith
   ```
2. Reset the password to a random value, so any cached credentials stop working.
3. Remove from all groups except `Domain Users`:
   ```powershell
   Get-ADUser jsmith -Properties MemberOf | Select -Expand MemberOf | ForEach-Object { Remove-ADGroupMember -Identity $_ -Members jsmith -Confirm:$false }
   ```
4. Add a note in the description (`Disabled 2026-11-03, ticket/reason`) and **move to** `_Lab > Users > Disabled`:
   ```powershell
   Move-ADObject -Identity (Get-ADUser jsmith).DistinguishedName -TargetPath 'OU=Disabled,OU=Users,OU=_Lab,DC=lab,DC=example,DC=com'
   ```
5. Archive their home folder from `\\FILE01\Home$` if needed.
6. After 30 days, delete the account. It remains recoverable via the AD Recycle Bin.

## Rollback

- Wrongly disabled: `Enable-ADAccount -Identity jsmith`, then move back to the right OU and re-add groups.
- Wrongly deleted: restore from the Recycle Bin ([active-directory.md](../services/active-directory.md#recovering-deleted-objects)).

## Escalation

Replication problems (new user not visible on the other DC): run `repadmin /replsummary`, then see [dc01.md](../servers/dc01.md).
