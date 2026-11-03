# Changelog

Dated log of changes to the lab. Newest first. Record **what changed, on which host, and why**, so you can trace when something broke.

## Format

```
## YYYY-MM-DD
- [HOST] What changed. Why. (Rollback: how, if non-obvious)
```

## 2026-11-03
- [repo] Added QEMU/KVM variant: `docs/qemu/` (host setup, networking, VMs, operations, troubleshooting) and `scripts/qemu/` (`lab.sh`, `net.sh`, `lab.conf`, `lab.service`). Scripts pass syntax checks and dry runs only, not yet tested on a real KVM host.
- [scripts] `Export-LabConfig.ps1` and `Get-LabHealth.ps1` gained `-SkipHyperV`. `Get-LabHealth.ps1` now falls back to a WinRM check when ICMP is blocked, instead of reporting FAIL.
- [repo] Initial documentation scaffold created: network, servers, services, runbooks, scripts.
