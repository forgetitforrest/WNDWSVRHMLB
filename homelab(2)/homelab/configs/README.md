# configs/

Sanitised exports of live configuration, produced by [`scripts/powershell/Export-LabConfig.ps1`](../scripts/powershell/Export-LabConfig.ps1).

**Review every export before committing.** Exports here are meant to be diffable text (CSV, HTML, TXT) so Git history shows exactly what changed and when.

| File | Contents |
|---|---|
| `dhcp-scopes.csv` | DHCP scopes and ranges |
| `dhcp-reservations.csv` | DHCP reservations |
| `dhcp-failover.csv` | DHCP failover relationship and state |
| `dns-zones.csv` | DNS zones and dynamic update settings |
| `dns-forwarders.csv` | DNS forwarders |
| `ad-ous.csv` | Organizational Unit tree |
| `ad-groups.csv` | Groups and scope |
| `ad-group-members.csv` | Membership of groups in the lab OU |
| `ad-users.csv` | Users (no password data) |
| `ad-domain-controllers.csv` | Domain controllers and FSMO roles |
| `gpo-reports/` | HTML reports for every GPO |
| `<host>-features.csv` | Installed Windows roles and features per host (e.g. `dc01-features.csv`) |
| `hyperv-vms.csv` | VM settings (CPU, memory, autostart, checkpoint type) |
| `hyperv-vm-vlans.csv` | VM network adapter VLAN assignments |

`gpo-backups/` is **git-ignored by default**, since full GPO backups can contain credentials.
