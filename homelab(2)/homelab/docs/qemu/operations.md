# QEMU Operations

## Daily commands

```bash
cd scripts/qemu
./lab.sh status              # VMs, bridges, taps
./lab.sh start all           # DC01, then DC02 and FILE01 (30 s apart)
./lab.sh start win11-01      # a VM without the 'autostart' flag
./lab.sh stop all            # graceful shutdown, reverse order (FILE01, DC02, DC01)
./lab.sh stop file01
./lab.sh console dc01        # how to connect to the screen
./lab.sh kill dc02           # hard stop: like pulling the power, last resort
```

`stop` sends an ACPI power-button event, which Windows turns into a clean shutdown once the power-button action is set ([vms.md](vms.md#settings-to-apply-in-every-windows-guest)). If a VM ignores it, look at its screen before using `kill`.

## Start the lab at boot

[`scripts/qemu/lab.service`](../../scripts/qemu/lab.service) is a systemd unit that creates the network, starts the autostart VMs, and shuts everything down cleanly at poweroff.

```bash
# edit <YOUR_USER> and the paths first
sudo cp scripts/qemu/lab.service /etc/systemd/system/lab.service
sudo systemctl daemon-reload
sudo systemctl enable --now lab.service
```

Check with `systemctl status lab.service` and `journalctl -u lab.service`.

## Snapshots

QEMU's counterpart to Hyper-V checkpoints is the qcow2 **internal snapshot**. `lab.sh` only takes them while the VM is **stopped**, which makes them consistent.

```bash
./lab.sh stop file01
./lab.sh snap create file01 pre-patch-2026-11
./lab.sh snap list file01
./lab.sh snap apply file01 pre-patch-2026-11      # roll back
./lab.sh snap delete file01 pre-patch-2026-11
```

- A snapshot covers **one disk file**. FILE01 has a data disk too, and the script snapshots only the OS disk (`file01.qcow2`). Don't revert the OS disk and keep newer data on the data disk without thinking it through.
- Snapshots grow the qcow2 file as the guest changes data. **Delete them once the change is verified.**
- Snapshots are **not backups**. They live in the same file as the disk.

### Domain controllers: don't revert snapshots

`lab.sh snap` refuses to act on VMs flagged `dc`. Reverting a DC to an older state makes it replay old Active Directory updates (USN rollback) and can corrupt replication. Prefer a **backup restore** or **rebuild and re-promote**, as described in [dc02.md](../servers/dc02.md#if-dc01-is-permanently-lost) and [restore-from-backup.md](../runbooks/restore-from-backup.md).

DC VMs have a **VM-Generation ID** (`vmgenid`) in `lab.conf` so Windows can detect a revert or clone and apply its virtualization safeguards. This only works if you **change the GUID** whenever the disk goes back in time:

```bash
uuidgen                          # copy the new GUID into the DC's line in lab.conf
```

Do this after any snapshot revert, disk restore, or disk clone of a DC, **before** its next boot. Leave it alone during normal reboots.

To override the block anyway: `ALLOW_DC_SNAPSHOT=1 ./lab.sh snap create dc02 test`. Only do this on a throwaway lab.

## Backups

Use layers. The first one matters most.

| Layer | What | How |
|---|---|---|
| 1. In-guest | Windows Server Backup of System State, volumes, shares | Unchanged, see [backup.md](../services/backup.md). Back up to the NAS over the network. |
| 2. Host-level cold copy | The qcow2 files, for fast whole-VM recovery | Stop the VM, copy, start it |
| 3. Config | `lab.conf`, scripts, docs | This Git repo |

### Host-level cold copy

```bash
./lab.sh stop file01
cp --sparse=always /srv/lab/disks/file01*.qcow2 /mnt/backup/lab/$(date +%F)/
./lab.sh start file01
```

Or compress while copying: `qemu-img convert -O qcow2 -c file01.qcow2 /mnt/backup/lab/file01.qcow2`. A running VM's disk file is **not** consistent to copy, so don't.

For DCs, rely on in-guest System State backups instead of copying disks, and see the VM-Generation ID note above if you ever restore a DC's disk.

### Restoring a VM from a host-level copy

```bash
./lab.sh stop file01                       # or kill it if it is unresponsive
cp --sparse=always /mnt/backup/lab/2026-11-02/file01*.qcow2 /srv/lab/disks/
./lab.sh start file01
```

## Disk resize

```bash
./lab.sh stop file01
qemu-img resize /srv/lab/disks/file01-data.qcow2 +200G
./lab.sh start file01
```

Then in Windows:

```powershell
Resize-Partition -DriveLetter E -Size (Get-PartitionSupportedSize -DriveLetter E).SizeMax
```

You cannot shrink a qcow2 safely this way. Shrink the partition first, then use `qemu-img resize --shrink`, and take a backup before trying.

## Health checks

```bash
./lab.sh status
```

```powershell
.\scripts\powershell\Get-LabHealth.ps1 -SkipHyperV
.\scripts\powershell\Export-LabConfig.ps1 -SkipHyperV -Servers DC01,DC02,FILE01
```

`-SkipHyperV` leaves out the Hyper-V host and the Hyper-V VM checks, which don't apply here.

## Hyper-V runbooks and their QEMU equivalents

| Hyper-V doc | What changes in QEMU |
|---|---|
| [hyperv-host01.md](../servers/hyperv-host01.md) | Replaced by [host-setup.md](host-setup.md) and [vms.md](vms.md). Keep only one in your repo. |
| [new-vm.md](../runbooks/new-vm.md) | Step 1 (create the VM) becomes the [overlay-disk procedure](vms.md#build-a-new-vm-from-it). Steps 2 onward (rename, IP, join domain, post-build) are the same. |
| [patch-cycle.md](../runbooks/patch-cycle.md) | Same order and verification. In step 2, "checkpoint" means `lab.sh snap create` on a **stopped** non-DC VM (or just rely on backups). In step 4, "patch HV01 last" becomes: `./lab.sh stop all`, update and reboot the Linux host, `sudo ./net.sh up`, `./lab.sh start all`. |
| [restore-from-backup.md](../runbooks/restore-from-backup.md) | File and AD restores are unchanged. For a VM, use [restoring from a host-level copy](#restoring-a-vm-from-a-host-level-copy), or rebuild a DC rather than restoring it. |
| [backup.md](../services/backup.md) | In-guest backups unchanged. Add the host-level cold copy above. The HV01 "VMs" backup row does not apply. |
| [topology.md](../network/topology.md) | VLAN design is the same. Layer 2 is Linux bridges instead of tags, and the host is the router ([networking.md](networking.md)). |

Add a dated [CHANGELOG](../../CHANGELOG.md) line for every host change: package updates, firmware path changes, network changes.
