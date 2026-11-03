# Group Policy

| | |
|---|---|
| **Management** | Group Policy Management Console (GPMC) on DC01 or the admin workstation |
| **ADMX central store** | `\\lab.example.com\SYSVOL\lab.example.com\Policies\PolicyDefinitions` |
| **Naming** | `GPO-<Scope>-<Purpose>` |
| **Last reviewed** | 2026-11-03 |

## GPO inventory

| GPO | Linked to | Purpose | Key settings |
|---|---|---|---|
| Default Domain Policy | Domain root | Domain-wide password and Kerberos policy | Password and lockout policy only. Keep everything else out of it. |
| Default Domain Controllers Policy | Domain Controllers OU | Built-in DC policy | Leave default, change only deliberately |
| GPO-Servers-Baseline | `_Lab/Computers/Servers` | Hardening and standard config | Windows Firewall on, RDP with NLA only, SMBv1 off, advanced audit policy, Windows Update schedule |
| GPO-Workstations-Baseline | `_Lab/Computers/Workstations` | Standard client config | Screen lock after 15 min, Windows Update, Defender settings, local admin restrictions |
| GPO-Users-DriveMaps | `_Lab/Users/Staff` | Map network drives | H: to `\\FILE01\Home$\%username%`, S: to `\\FILE01\Dept` |
| GPO-Admins-Restrictions | `_Lab/Users/Admins` | Contain admin accounts | Deny logon to workstations *(optional)* |

*(Update this table every time a GPO is created, linked, or changed.)*

## Rules of thumb

- **One purpose per GPO.** Easier to troubleshoot and to disable.
- **Don't edit the Default policies** beyond what's listed above.
- **Link to OUs, not the domain root,** unless the setting really is domain-wide.
- **Test on one machine or a test OU first,** then link wider.
- **Disable unused sections** (User or Computer settings) in a GPO that only uses one.
- **Never store passwords in Group Policy Preferences.** They are decryptable by any domain user.

## Common commands

```powershell
# Inventory
Get-GPO -All | Select DisplayName, GpoStatus, ModificationTime | Sort ModificationTime -Descending

# Where is a GPO linked?
Get-GPOReport -Name 'GPO-Servers-Baseline' -ReportType Xml |
    Select-String '<LinksTo>' -Context 0,3

# Force an update and see what applied (on a client)
gpupdate /force
gpresult /r
gpresult /h "$env:TEMP\gpresult.html"

# Export reports for the repo
Get-GPO -All | ForEach-Object { Get-GPOReport -Guid $_.Id -ReportType Html -Path ".\configs\gpo-reports\$($_.DisplayName).html" }
```

## Create the central store (once)

```powershell
# Copy the ADMX/ADML files from a recent Windows client (C:\Windows\PolicyDefinitions)
Copy-Item 'C:\Windows\PolicyDefinitions\*' '\\lab.example.com\SYSVOL\lab.example.com\Policies\PolicyDefinitions' -Recurse -Force
```

## Known issues / notes

- *(none yet)*
