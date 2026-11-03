# scripts/powershell

| Script | Purpose | Needs |
|---|---|---|
| `Export-LabConfig.ps1` | Export DHCP, DNS, AD, GPO, features, and VM settings to `configs/` | RSAT modules (AD, GroupPolicy, DhcpServer, DnsServer, Hyper-V), admin rights |
| `New-LabUser.ps1` | Create a standard AD user with a random temporary password | ActiveDirectory module, rights on the target OU |
| `Get-LabHealth.ps1` | Health check across hosts, AD, DHCP, and VMs | WinRM to each host, admin rights |

## Not using Hyper-V?

Pass `-SkipHyperV` to `Export-LabConfig.ps1` and `Get-LabHealth.ps1` (for example on the [QEMU/KVM version of the lab](../../docs/qemu/README.md)). VM state there comes from `scripts/qemu/lab.sh status`.

## Before first use

1. Edit the defaults at the top of each script (`$LabHosts`, `-OU`, `-Domain`, host names) to match your lab.
2. Run from an **elevated** PowerShell session on a DC or a domain-joined admin machine.
3. If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Safe testing

`New-LabUser.ps1` supports `-WhatIf`:

```powershell
.\New-LabUser.ps1 -GivenName Jane -Surname Smith -WhatIf
```

## Rules for scripts in this repo

- **No credentials in scripts.** Use `Get-Credential` or the Windows credential store.
- Keep comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) up to date.
- Prefer read-only scripts; anything that changes state should support `-WhatIf`.
