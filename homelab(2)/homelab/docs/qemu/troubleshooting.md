# QEMU Troubleshooting

## Quick checks

```bash
./lab.sh status                          # VM, bridge, and tap state
./net.sh status
DRY_RUN=1 ./lab.sh start dc01            # shows the exact QEMU command line
bridge link                              # taps attached to the right bridges?
ls -l /dev/kvm
sudo nft list ruleset | head -50
```

## Host and startup

| Symptom | Likely cause | Fix |
|---|---|---|
| `Could not access KVM kernel module: Permission denied` | Your user is not in the `kvm` group | `sudo usermod -aG kvm $USER`, then log out and in |
| `/dev/kvm` does not exist | Virtualization disabled in firmware, or nested virtualization off | Enable VT-x/AMD-V; on a VM host, enable nested virtualization |
| `error: network device tap-dc01 not found` | `net.sh up` has not run (for example after a reboot) | `sudo ./net.sh up` |
| `could not configure /dev/net/tun (tap-dc01): Operation not permitted` | The tap is owned by a different user | `sudo ./net.sh down`, then `sudo LAB_USER=$USER ./net.sh up` |
| `UEFI firmware not found: ...` | `OVMF_CODE` path is wrong for your distro | `ls /usr/share/OVMF /usr/share/edk2/ovmf`, fix `lab.conf` |
| `qemu-system-x86_64: command not found` | QEMU not installed, or a different binary name | Install packages ([host-setup.md](host-setup.md)); set `QEMU_BIN` |
| `Failed to get "write" lock` | VM already running, or disk opened by another process | `./lab.sh status`; check for another QEMU using the file |
| VNC shows a black screen | UEFI is still starting, or no VGA device | Wait 10-20 s; the scripts use `-device VGA`. Click the window and press a key. |

## Windows install

| Symptom | Likely cause | Fix |
|---|---|---|
| Installer shows no disks | No storage driver | **Load driver** > virtio CD > `viostor\2k22\amd64` |
| Loops back to the installer after the first reboot | You pressed a key at *Press any key to boot from CD* | Let that prompt time out so it boots from disk |
| "This PC can't run Windows 11" | No TPM or Secure Boot | Use the `tpm,secboot` flags, check `swtpm` is installed and the secboot firmware paths in `lab.conf` |
| Windows 11 installer can't see the disk | Wrong driver folder | `viostor\w11\amd64` |

## Networking

| Symptom | Likely cause | Fix |
|---|---|---|
| Guest has no network adapter / "Unidentified network" | NetKVM driver missing | Run `virtio-win-guest-tools.exe` from the virtio ISO (install mode keeps it attached) |
| Guest cannot reach its gateway `10.0.20.1` | Tap not on the bridge, or wrong IP | `bridge link`; `ip addr show br-servers`; re-run `sudo ./net.sh up` |
| VMs can reach each other but not the internet | Forwarding or NAT missing | `sysctl net.ipv4.ip_forward` should be 1; `sudo nft list table ip lab_nat`; check the right uplink with `ip route show default` |
| Internet breaks only when Docker is installed | Docker sets the iptables `FORWARD` policy to `DROP` | Allow the lab bridges, for example: `sudo iptables -I DOCKER-USER -i br-servers -j ACCEPT` and `sudo iptables -I DOCKER-USER -o br-servers -j ACCEPT`, same for `br-clients` |
| Clients get `169.254.x.x` | No DHCP relay, or relay not running | [networking.md](networking.md#dhcp-for-the-clients-vlan); run `dhcrelay -d` in the foreground and watch |
| Clients get an address but cannot join the domain | Client DNS isn't the DCs, or the optional firewall is dropping traffic | Check `ipconfig /all` for `10.0.20.10/.11`; temporarily remove the `lab_fw` nftables table |
| Ping to another VM fails but the service works | Windows Firewall blocks ICMP by default | Test with `Test-NetConnection <ip> -Port 445` instead |
| Two VMs have the same address | Duplicate MAC or static IP | Check the MAC plan in `lab.conf` and the [IP plan](../network/ip-plan.md) |

## Windows guest behaviour

| Symptom | Likely cause | Fix |
|---|---|---|
| `lab.sh stop` times out | Power-button action isn't "Shut down" | `powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 3` then `powercfg /setactive SCHEME_CURRENT`; check the screen for a blocking prompt |
| Clock off by hours | RTC/time zone mismatch | The scripts use `-rtc base=localtime`; set the guest time zone; on DC01 (PDC emulator) verify NTP with `w32tm /query /status` |
| Slow disk | Disk on a hard drive, or the host is swapping | Put `/srv/lab` on an SSD; check host RAM with `free -h` |
| `QEMU-GA` service missing | Guest tools not installed | Run `virtio-win-guest-tools.exe` |
| DC shows USN rollback events (Directory Service log) | A DC disk was reverted or cloned | Don't revert DCs. Rebuild and re-promote, see [dc02.md](../servers/dc02.md#if-dc01-is-permanently-lost) |

## When it is still broken

1. Capture the exact command: `DRY_RUN=1 ./lab.sh start <vm>`.
2. Run that QEMU command in the foreground (remove `-daemonize`) to see errors on the terminal.
3. Note the symptom and fix in the [CHANGELOG](../../CHANGELOG.md) so you recognise it next time.
