# QEMU VMs: Install and Build

VM definitions live in [`scripts/qemu/lab.conf`](../../scripts/qemu/lab.conf) and are started by [`lab.sh`](../../scripts/qemu/lab.sh). The VM table is the same as the Hyper-V one in [hyperv-host01.md](../servers/hyperv-host01.md#virtual-machines).

## VM definitions

| VM | vCPU | RAM | Bridge | MAC | Screen (VNC) | Flags |
|---|---|---|---|---|---|---|
| DC01 | 2 | 4 GB | br-servers | `52:54:00:20:00:10` | `127.0.0.1:5901` | autostart, dc |
| DC02 | 2 | 4 GB | br-servers | `52:54:00:20:00:11` | `127.0.0.1:5902` | autostart, dc |
| FILE01 | 2 | 4 GB | br-servers | `52:54:00:20:00:20` | `127.0.0.1:5903` | autostart |
| WIN11-01 | 2 | 4 GB | br-clients | `52:54:00:30:00:20` | `127.0.0.1:5904` | tpm, secboot |

### What the QEMU settings do

| Setting | Purpose |
|---|---|
| `-machine q35,accel=kvm` | Modern PC chipset, hardware acceleration |
| `-cpu host,hv_relaxed,hv_spinlocks=…,hv_vapic,hv_time` | Pass the host CPU through, and enable Hyper-V "enlightenments" so Windows behaves well and keeps accurate time as a guest |
| UEFI pflash drives (OVMF) | Generation 2-style UEFI boot; the second drive is the VM's private variable store |
| `virtio-blk-pci` disk | Fast paravirtualized disk (needs the `viostor` driver at install time) |
| `virtio-net-pci` NIC + tap | Fast paravirtualized network (needs the `NetKVM` driver) |
| `-rtc base=localtime` | Windows expects the hardware clock in local time |
| `qemu-xhci` + `usb-tablet` | Mouse pointer that tracks correctly over VNC |
| `-display none -vnc 127.0.0.1:N` | Headless; connect with a VNC client |
| QMP socket | Lets `lab.sh stop` send a graceful ACPI shutdown |
| Guest-agent channel | For the QEMU Guest Agent (installed with virtio tools), available for later automation |
| `vmgenid` (DCs only) | VM-Generation ID, so Windows can detect snapshot reverts and clones |
| `tpm` / `secboot` flags | Software TPM 2.0 and Secure Boot firmware for Windows 11 |

See the exact command for any VM with `DRY_RUN=1 ./lab.sh start dc01`.

## Create the disks

```bash
cd scripts/qemu
./lab.sh init
```

This creates sparse qcow2 files from `DISK_SIZES` and `EXTRA_DISKS` in `lab.conf` (for example `dc01.qcow2`, `file01.qcow2`, `file01-data.qcow2`). Existing files are skipped.

## Install Windows Server

Repeat for each Windows Server VM (DC01, DC02, FILE01).

1. **Boot the installer.**
   ```bash
   ./lab.sh install dc01
   ./lab.sh console dc01        # prints the VNC address and an SSH-tunnel hint
   ```
   Connect with a VNC client (`remote-viewer vnc://127.0.0.1:5901`, Remmina, TigerVNC, and so on). If the screen says *Press any key to boot from CD or DVD*, click the window and press a key **quickly**.
2. **Setup wizard.** Choose language, **Install now**, **I don't have a product key** (evaluation), and pick **Windows Server 2022 Standard Evaluation (Desktop Experience)**. Accept the license and choose **Custom: Install Windows only**.
3. **No disks listed? That is expected.** Windows does not include a virtio storage driver.
   - Click **Load driver** > **Browse**.
   - Open the virtio CD and go to `viostor` > `2k22` > `amd64`.
   - Select **Red Hat VirtIO SCSI controller** and continue. The 60 GB disk appears.
4. **Install.** The VM reboots a couple of times. When it shows *Press any key to boot from CD or DVD* again, **do nothing** so it boots from the disk.
5. **Set the Administrator password** and store it in your password manager, not in this repo.
6. **Install the virtio drivers and guest agent.** Still in install mode (both ISOs are attached), open the virtio CD in File Explorer and run `virtio-win-guest-tools.exe` (or `virtio-win-gt-x64.msi`). This installs the network driver (NetKVM), the balloon and serial drivers, and the QEMU Guest Agent. Accept the defaults and reboot if asked.
7. **Shut down and switch to normal mode.**
   ```bash
   ./lab.sh stop dc01
   ./lab.sh start dc01          # no ISOs attached now
   ```

### Settings to apply in every Windows guest

Run in an elevated PowerShell:

```powershell
# Time zone
Set-TimeZone -Id 'Eastern Standard Time'      # your zone: Get-TimeZone -ListAvailable

# Make the ACPI power button do a clean shutdown (needed for 'lab.sh stop')
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 3
powercfg /setactive SCHEME_CURRENT

# Remote management
Enable-PSRemoting -Force
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0

# Name and address (example for DC01)
Rename-Computer -NewName 'DC01'
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.20.10 -PrefixLength 24 -DefaultGateway 10.0.20.1
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 127.0.0.1     # first DC points at itself
Restart-Computer
```

Run Windows Update, then confirm the guest agent is running: `Get-Service QEMU-GA`.

## Build the lab in order

The Windows-side steps are the same as on Hyper-V. Follow them in this order:

| Step | What | Where it is documented |
|---|---|---|
| 1 | **DC01**: install AD DS + DNS and create the forest | below |
| 2 | Create OUs, groups, password policy | [active-directory.md](../services/active-directory.md) |
| 3 | DNS forwarders | [dns-dhcp.md](../services/dns-dhcp.md#forwarders) |
| 4 | **DC02**: join and promote | below |
| 5 | **Update DNS settings**: DC01 now uses `10.0.20.11` then itself; DC02 uses `10.0.20.10` then itself | [ip-plan.md](../network/ip-plan.md#dns-settings-on-every-domain-joined-machine) |
| 6 | DHCP scope and failover | [dns-dhcp.md](../services/dns-dhcp.md#dhcp) |
| 7 | DHCP relay on the **host** for the Clients VLAN | [networking.md](networking.md#dhcp-for-the-clients-vlan) |
| 8 | **FILE01**: join domain, create the data volume and shares | below, then [file01.md](../servers/file01.md) |
| 9 | Group Policy baselines | [group-policy.md](../services/group-policy.md) |
| 10 | Backups, then a test restore | [backup.md](../services/backup.md) |
| 11 | Client (optional) | below |
| 12 | Export the config and commit | `Export-LabConfig.ps1 -SkipHyperV` |

### DC01: create the forest

```powershell
Install-WindowsFeature AD-DS, DNS, DHCP -IncludeManagementTools
Install-ADDSForest -DomainName 'lab.example.com' -DomainNetbiosName 'LAB' `
    -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns `
    -SafeModeAdministratorPassword (Read-Host -AsSecureString 'DSRM password')
```

`WinThreshold` is the Windows Server 2016 functional level, the highest Server 2022 offers. The server reboots. Store the DSRM password in your password manager.

### DC02: join and promote

```powershell
# Point DNS at DC01 first
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 10.0.20.10
Install-WindowsFeature AD-DS, DNS, DHCP -IncludeManagementTools
Install-ADDSDomainController -DomainName 'lab.example.com' -InstallDns -Credential (Get-Credential 'LAB\Administrator')
```

You will be prompted for the DSRM password. Verify with `dcdiag /q` and `repadmin /replsummary`.

### FILE01: data disk and domain join

```powershell
# Initialize and format the 500 GB data disk as E:
Get-Disk | Where-Object PartitionStyle -eq 'RAW' |
    Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter E -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data'

# Join the domain
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 10.0.20.10,10.0.20.11
Add-Computer -DomainName 'lab.example.com' -Credential (Get-Credential 'LAB\Administrator') -Restart
```

### Windows 11 client (optional)

Windows 11 needs a TPM 2.0 and Secure Boot. The `tpm,secboot` flags in `lab.conf` start a software TPM (`swtpm`) and the Secure Boot firmware for you.

```bash
./lab.sh install win11-01
```

The storage driver for the installer is in `viostor` > `w11` > `amd64` on the virtio CD. The client gets its address from DHCP on `br-clients`, so the DHCP relay must be working first.

## Templates and new VMs

A **template** is a sysprepped qcow2 used as a read-only **backing file**. Each new VM is a thin overlay on top of it, so creating a VM takes seconds and uses little space.

### Make the template (once)

1. Install Windows Server on a scratch VM with the virtio drivers and guest tools, fully patched.
2. Generalize and shut down:
   ```powershell
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
   ```
3. Move and protect the disk:
   ```bash
   mv /srv/lab/disks/<scratch>.qcow2 /srv/lab/disks/WS2022-template.qcow2
   chmod a-w /srv/lab/disks/WS2022-template.qcow2
   ```

**Never boot or modify the template again.** Every VM built on it depends on it staying exactly as it is. To update it, make a new template file.

### Build a new VM from it

1. Create the overlay disk:
   ```bash
   qemu-img create -f qcow2 -F qcow2 -b /srv/lab/disks/WS2022-template.qcow2 /srv/lab/disks/app01.qcow2 60G
   ```
2. Add a line to `VMS` in `lab.conf` with a unique MAC and VNC display:
   ```bash
   "app01|2|4G|br-servers|52:54:00:20:00:40|5|autostart|"
   ```
3. Add a size to `DISK_SIZES` if you want `lab.sh init` to know about it, then create its network device:
   ```bash
   sudo ./net.sh up
   ./lab.sh start app01
   ```
4. Finish setup over VNC (name, static IP, domain join) using the steps in [new-vm.md](../runbooks/new-vm.md#2-first-boot-inside-the-vm) from "First boot" onward.
5. Update the IP plan, add the VM to the backup policy and `$LabHosts`, and add a [CHANGELOG](../../CHANGELOG.md) line.

> If a new overlay disk is larger than the template's virtual size, extend the partition inside Windows after first boot.
