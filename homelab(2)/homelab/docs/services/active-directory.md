# Active Directory

| | |
|---|---|
| **Domain (DNS)** | `lab.example.com` *(example)* |
| **Domain (NetBIOS)** | `LAB` |
| **Forest / domain functional level** | Windows Server 2016 *(highest available for Server 2022)* |
| **Domain controllers** | DC01, DC02 ([dc01.md](../servers/dc01.md), [dc02.md](../servers/dc02.md)) |
| **Sites** | Default-First-Site-Name (single site) |
| **AD Recycle Bin** | Enabled |
| **Last reviewed** | 2026-11-03 |

> **Domain naming:** avoid `.local` for a new domain. It collides with multicast DNS (mDNS) and causes odd resolution problems. A subdomain of a name you own (e.g. `lab.<yourdomain>.com`) is the usual recommendation. `lab.example.com` here is a placeholder.

## OU structure

```
lab.example.com
├── Domain Controllers            (built-in)
└── _Lab
    ├── Users
    │   ├── Staff
    │   ├── Admins                (adm-* accounts)
    │   └── Disabled              (offboarded, pending deletion)
    ├── Computers
    │   ├── Servers
    │   └── Workstations
    ├── Groups
    │   ├── Global                (GG-*)
    │   └── DomainLocal           (DL-*)
    └── ServiceAccounts           (svc-* accounts, gMSAs)
```

Create it with:

```powershell
$base = 'DC=lab,DC=example,DC=com'
New-ADOrganizationalUnit -Name '_Lab' -Path $base -ProtectedFromAccidentalDeletion $true
$lab = "OU=_Lab,$base"
'Users','Computers','Groups','ServiceAccounts' | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path $lab }
'Staff','Admins','Disabled' | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "OU=Users,$lab" }
'Servers','Workstations'    | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "OU=Computers,$lab" }
'Global','DomainLocal'      | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "OU=Groups,$lab" }
```

## Naming conventions

| Object | Pattern | Example |
|---|---|---|
| User | first initial + surname | `jsmith` |
| Admin account | `adm-` + username | `adm-jsmith` |
| Service account | `svc-<service>` (prefer gMSA) | `svc-backup` |
| Global group | `GG-<Dept or Role>` | `GG-IT`, `GG-AllStaff` |
| Domain local group | `DL-<Resource>-<Permission>` | `DL-Dept-Finance-Modify` |
| Server | `<ROLE><NN>` | `FILE01` |
| Workstation | `<TYPE>-<NN>` | `WIN11-01` |

## Group strategy (AGDLP)

**A**ccounts go into **G**lobal groups, global groups go into **D**omain **L**ocal groups, and domain local groups get **P**ermissions on resources.

```
jsmith  ->  GG-Finance  ->  DL-Dept-Finance-Modify  ->  NTFS Modify on \\FILE01\Dept\Finance
```

Never assign permissions to individual users. When someone changes role, you change their group membership and nothing else.

## Privileged accounts

- Daily accounts are standard users with no admin rights anywhere.
- Admin tasks use a separate `adm-<user>` account, a member of `Domain Admins` **only if needed**. Prefer delegated rights over Domain Admins.
- Admin accounts log on to servers and the admin workstation only, never to general clients.
- Consider adding admin accounts to **Protected Users**.
- Built-in `Administrator` is renamed or disabled, with a long random password stored in the password manager.

## FSMO roles

| Role | Holder |
|---|---|
| Schema Master | DC01 |
| Domain Naming Master | DC01 |
| PDC Emulator | DC01 |
| RID Master | DC01 |
| Infrastructure Master | DC01 |

Check with `netdom query fsmo`. All roles on one DC is normal for a small lab.

## Password policy

Set in the **Default Domain Policy** (see [group-policy.md](group-policy.md)):

| Setting | Value |
|---|---|
| Minimum length | 14 |
| Complexity | Enabled |
| Maximum age | 365 days *(or none, if you rely on length and MFA)* |
| Lockout threshold | 10 attempts |
| Lockout duration / reset | 15 minutes |

A Fine-Grained Password Policy (PSO) can apply a stricter policy to the `adm-*` accounts.

## Recovering deleted objects

With the AD Recycle Bin enabled, deleted objects are recoverable for 180 days:

```powershell
# Enable once (irreversible)
Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target 'lab.example.com'

# Find and restore
Get-ADObject -Filter 'isDeleted -eq $true -and Name -like "*jsmith*"' -IncludeDeletedObjects |
    Restore-ADObject
```

For anything bigger, see [Restore from backup](../runbooks/restore-from-backup.md).

## Health checks

```powershell
dcdiag /q
repadmin /replsummary
repadmin /showrepl
Get-ADDomainController -Filter * | Select Name, IPv4Address, IsGlobalCatalog, OperatingSystem
```

## Known issues / notes

- *(none yet)*
