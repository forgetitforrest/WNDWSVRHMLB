# Runbook: Build a New VM from the Template

> **Hypervisor:** this runbook uses Hyper-V. On QEMU/KVM, do step 1 with the [overlay-disk procedure](../qemu/vms.md#build-a-new-vm-from-it) and continue from step 2.

## When to use

Adding a new Windows Server VM (member server, test box) to the lab.

## Prerequisites

- Admin on HV01.
- A sysprepped golden image at `D:\Hyper-V\Templates\WS2022-Gen2.vhdx` (read-only).
- A free IP in the [IP plan](../network/ip-plan.md) and a hostname following the convention.
- Domain admin credentials (`adm-*`) for the join.

## Procedure

### 1. Create the VM (on HV01)

```powershell
$name = 'APP01'          # new hostname
$vlan = 20               # 20 = Servers
Copy-Item 'D:\Hyper-V\Templates\WS2022-Gen2.vhdx' "D:\Hyper-V\VHDX\$name.vhdx"
New-VM -Name $name -Generation 2 -MemoryStartupBytes 4GB -VHDPath "D:\Hyper-V\VHDX\$name.vhdx" `
       -SwitchName 'vSwitch-External' -Path 'D:\Hyper-V\VMs'
Set-VMProcessor -VMName $name -Count 2
Set-VMNetworkAdapterVlan -VMName $name -Access -VlanId $vlan
Set-VM -Name $name -AutomaticStartAction StartIfRunning -AutomaticStartDelay 90 -AutomaticStopAction ShutDown
Start-VM -Name $name
```

### 2. First boot (inside the VM)

Complete the out-of-box setup, set a local Administrator password (store it in the password manager), then:

```powershell
Rename-Computer -NewName 'APP01'
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.20.40 -PrefixLength 24 -DefaultGateway 10.0.20.1
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 10.0.20.10,10.0.20.11
Restart-Computer
```

### 3. Join the domain

```powershell
Add-Computer -DomainName 'lab.example.com' `
    -OUPath 'OU=Servers,OU=Computers,OU=_Lab,DC=lab,DC=example,DC=com' `
    -Credential (Get-Credential) -Restart
```

### 4. Post-build

- [ ] Run Windows Update to current.
- [ ] Confirm `GPO-Servers-Baseline` applied (`gpresult /r`).
- [ ] Confirm DNS record exists: `Resolve-DnsName app01.lab.example.com`.
- [ ] Add the VM to the backup policy ([backup.md](../services/backup.md)).
- [ ] Add the host to `$LabHosts` in `Get-LabHealth.ps1`.
- [ ] Copy [`docs/servers/_template.md`](../servers/_template.md) to `docs/servers/app01.md` and fill it in.
- [ ] Add the IP to [ip-plan.md](../network/ip-plan.md).
- [ ] Add a dated line to [CHANGELOG.md](../../CHANGELOG.md).

## Rollback

```powershell
Stop-VM -Name APP01 -TurnOff
Remove-VM -Name APP01 -Force
Remove-Item 'D:\Hyper-V\VHDX\APP01.vhdx'
```

If it was domain-joined, also delete the computer object in AD (and its DNS records).

## Escalation

Join fails with "domain not found": check the VM's DNS servers are the DCs, the VLAN tag is right, and the firewall allows VLAN 20 to DCs ([topology](../network/topology.md)).
