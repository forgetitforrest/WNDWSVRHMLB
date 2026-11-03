<#
.SYNOPSIS
    Quick health check of the lab: reachability, key services, disk space, uptime, backup age,
    AD replication, DHCP failover, and Hyper-V VM state.

.DESCRIPTION
    Edit the $LabHosts list below to match your lab. Remote checks use PowerShell remoting (WinRM),
    which is enabled by default on Windows Server. Run from a domain-joined machine as an admin.

    Exit code is 0 if there are no FAIL results, 1 otherwise, so it can be used in scheduled tasks.

.PARAMETER DiskWarnPercent
    Warn when free space on a fixed volume drops below this percentage.

.PARAMETER SkipHyperV
    Skip the Hyper-V host and VM checks. Use this when the lab runs on QEMU/KVM or any
    non-Hyper-V hypervisor (check VM state there with scripts/qemu/lab.sh status).

.PARAMETER BackupMaxAgeHours
    Warn when the last successful Windows Server Backup is older than this.

.EXAMPLE
    .\Get-LabHealth.ps1
#>
[CmdletBinding()]
param(
    [int]$DiskWarnPercent = 20,
    [int]$BackupMaxAgeHours = 36,
    [string]$HyperVHost = 'HV01',
    [string]$DhcpServer = 'DC01',
    [string[]]$ExpectedRunningVMs = @('DC01', 'DC02', 'FILE01'),
    [switch]$SkipHyperV
)

# ---- Edit to match your lab -------------------------------------------------
$LabHosts = @(
    [pscustomobject]@{ Name = 'HV01';   Services = @('vmms') }
    [pscustomobject]@{ Name = 'DC01';   Services = @('NTDS', 'DNS', 'Netlogon', 'kdc', 'DHCPServer') }
    [pscustomobject]@{ Name = 'DC02';   Services = @('NTDS', 'DNS', 'Netlogon', 'kdc', 'DHCPServer') }
    [pscustomobject]@{ Name = 'FILE01'; Services = @('LanmanServer') }
)
# -----------------------------------------------------------------------------

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Target, [string]$Check, [ValidateSet('OK', 'WARN', 'FAIL')][string]$Status, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Target = $Target; Check = $Check; Status = $Status; Detail = $Detail })
}

# ---------------- Per-host checks ----------------
$hostsToCheck = $LabHosts | Where-Object { -not ($SkipHyperV -and $_.Name -eq $HyperVHost) }

foreach ($h in $hostsToCheck) {
    $name = $h.Name

    # Windows Server blocks ICMP echo by default, so fall back to a WinRM check before calling it a failure
    if (Test-Connection -ComputerName $name -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Add-Result $name 'Ping' 'OK'
    }
    elseif (Test-WSMan -ComputerName $name -ErrorAction SilentlyContinue) {
        Add-Result $name 'Ping' 'OK' 'ICMP blocked (Windows Firewall default), WinRM reachable'
    }
    else {
        Add-Result $name 'Ping' 'FAIL' 'No reply to ICMP or WinRM'
        continue
    }

    try {
        $data = Invoke-Command -ComputerName $name -ArgumentList (, $h.Services) -ErrorAction Stop -ScriptBlock {
            param($svcNames)
            $svc = foreach ($s in $svcNames) {
                $x = Get-Service -Name $s -ErrorAction SilentlyContinue
                [pscustomobject]@{ Name = $s; Status = $(if ($x) { "$($x.Status)" } else { 'Missing' }) }
            }
            $disks = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } |
                Select-Object DriveLetter, Size, SizeRemaining
            $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
            $backup = try { Get-WBSummary } catch { $null }
            [pscustomobject]@{
                Services   = @($svc)
                Disks      = @($disks)
                BootTime   = $boot
                BackupTime = if ($backup) { $backup.LastSuccessfulBackupTime } else { $null }
                BackupHR   = if ($backup) { $backup.LastBackupResultHR } else { $null }
            }
        }
    }
    catch {
        Add-Result $name 'Remoting' 'FAIL' $_.Exception.Message
        continue
    }

    # Services
    foreach ($s in $data.Services) {
        $status = if ($s.Status -eq 'Running') { 'OK' } else { 'FAIL' }
        Add-Result $name "Service: $($s.Name)" $status $s.Status
    }

    # Disk space
    foreach ($d in $data.Disks) {
        if ($d.Size -gt 0) {
            $pct = [math]::Round(100 * $d.SizeRemaining / $d.Size, 0)
            $freeGB = [math]::Round($d.SizeRemaining / 1GB, 1)
            $status = if ($pct -lt $DiskWarnPercent) { 'WARN' } else { 'OK' }
            Add-Result $name "Disk $($d.DriveLetter):" $status "$pct% free ($freeGB GB)"
        }
    }

    # Uptime
    $uptime = (Get-Date) - $data.BootTime
    Add-Result $name 'Uptime' 'OK' ('{0}d {1}h' -f $uptime.Days, $uptime.Hours)

    # Backup (only reported if Windows Server Backup has run on the host)
    if ($data.BackupTime) {
        $age = [math]::Round(((Get-Date) - $data.BackupTime).TotalHours, 0)
        if ($data.BackupHR -ne 0) {
            Add-Result $name 'Backup' 'FAIL' ('Last result code {0}, last success {1}' -f $data.BackupHR, $data.BackupTime)
        }
        elseif ($age -gt $BackupMaxAgeHours) {
            Add-Result $name 'Backup' 'WARN' "Last success $age h ago"
        }
        else {
            Add-Result $name 'Backup' 'OK' "Last success $age h ago"
        }
    }
    else {
        Add-Result $name 'Backup' 'WARN' 'No Windows Server Backup history found'
    }
}

# ---------------- Active Directory replication ----------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    foreach ($dc in Get-ADDomainController -Filter *) {
        $failures = @(Get-ADReplicationFailure -Target $dc.HostName -ErrorAction Stop)
        if ($failures.Count -gt 0) {
            Add-Result $dc.Name 'AD replication' 'FAIL' ("{0} failure(s), first partner: {1}" -f $failures.Count, $failures[0].Partner)
        }
        else {
            Add-Result $dc.Name 'AD replication' 'OK' 'No failures'
        }
    }
}
catch {
    Add-Result 'AD' 'AD replication' 'WARN' "Could not check: $($_.Exception.Message)"
}

# ---------------- DHCP failover ----------------
try {
    foreach ($f in Get-DhcpServerv4Failover -ComputerName $DhcpServer -ErrorAction Stop) {
        $status = if ("$($f.State)" -eq 'Normal') { 'OK' } else { 'WARN' }
        Add-Result $DhcpServer "DHCP failover: $($f.Name)" $status "$($f.State)"
    }
}
catch {
    Add-Result $DhcpServer 'DHCP failover' 'WARN' "Could not check: $($_.Exception.Message)"
}

# ---------------- Hyper-V VMs ----------------
if (-not $SkipHyperV) {
    try {
        foreach ($vm in Get-VM -ComputerName $HyperVHost -ErrorAction Stop) {
            $running = "$($vm.State)" -eq 'Running'
            $status = if ($running) { 'OK' }
                      elseif ($vm.Name -in $ExpectedRunningVMs) { 'FAIL' }
                      else { 'OK' }
            Add-Result $HyperVHost "VM: $($vm.Name)" $status "$($vm.State)"
        }
    }
    catch {
        Add-Result $HyperVHost 'Hyper-V VMs' 'WARN' "Could not check: $($_.Exception.Message)"
    }
}

# ---------------- Report ----------------
$results | Format-Table Target, Check, Status, Detail -AutoSize

$fail = @($results | Where-Object Status -eq 'FAIL').Count
$warn = @($results | Where-Object Status -eq 'WARN').Count
$color = if ($fail) { 'Red' } elseif ($warn) { 'Yellow' } else { 'Green' }
Write-Host ("Summary: {0} checks, {1} FAIL, {2} WARN" -f $results.Count, $fail, $warn) -ForegroundColor $color

if ($fail -gt 0) { exit 1 } else { exit 0 }
