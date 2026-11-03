<#
.SYNOPSIS
    Exports lab configuration to diffable text files in configs/ so changes can be committed to Git.

.DESCRIPTION
    Exports DHCP, DNS, Active Directory, Group Policy, installed Windows features, and Hyper-V VM
    settings. Each export runs independently: if one fails (module missing, host unreachable) it is
    skipped with a warning and the rest continue.

    Nothing exported here contains passwords. Full GPO backups CAN contain sensitive data, so they
    are only created with -IncludeGpoBackups, and configs/gpo-backups/ is git-ignored by default.

    Run from an elevated PowerShell session on a DC or an admin machine with RSAT installed:
    ActiveDirectory, GroupPolicy, DhcpServer, DnsServer, and Hyper-V modules.

.PARAMETER OutputPath
    Where to write the exports. Defaults to <repo>/configs.

.PARAMETER DhcpServer
    Server to export DHCP settings from.

.PARAMETER DnsServer
    Server to export DNS settings from.

.PARAMETER Servers
    Servers to export installed roles/features from.

.PARAMETER HyperVHost
    Hyper-V host to export VM settings from.

.PARAMETER LabOU
    Name of the top-level lab OU, used to scope the group membership export.

.PARAMETER SkipHyperV
    Skip the Hyper-V VM exports and leave the Hyper-V host out of the per-server feature export.
    Use this when the lab runs on QEMU/KVM or any non-Hyper-V hypervisor.

.PARAMETER IncludeGpoBackups
    Also run Backup-GPO into configs/gpo-backups/. Review before committing.

.EXAMPLE
    .\Export-LabConfig.ps1

.EXAMPLE
    .\Export-LabConfig.ps1 -Servers DC01,DC02,FILE01 -IncludeGpoBackups
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\configs'),
    [string]$DhcpServer = 'DC01',
    [string]$DnsServer = 'DC01',
    [string[]]$Servers = @('HV01', 'DC01', 'DC02', 'FILE01'),
    [string]$HyperVHost = 'HV01',
    [string]$LabOU = '_Lab',
    [switch]$SkipHyperV,
    [switch]$IncludeGpoBackups
)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path

function Invoke-Export {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        $ErrorActionPreference = 'Stop'
        & $Action
        Write-Host "[ OK ] $Label" -ForegroundColor Green
    }
    catch {
        Write-Warning "[SKIP] $Label : $($_.Exception.Message)"
    }
}

function Save-Csv {
    param([Parameter(Mandatory, ValueFromPipeline)]$InputObject, [Parameter(Mandatory)][string]$Name)
    begin { $items = @() }
    process { $items += $InputObject }
    end {
        $items | Export-Csv -Path (Join-Path $OutputPath $Name) -NoTypeInformation -Encoding UTF8
    }
}

Write-Host "Exporting lab configuration to $OutputPath" -ForegroundColor Cyan

# ---------------- DHCP ----------------
Invoke-Export 'DHCP scopes' {
    Get-DhcpServerv4Scope -ComputerName $DhcpServer |
        Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State, LeaseDuration |
        Sort-Object ScopeId | Save-Csv -Name 'dhcp-scopes.csv'
}

Invoke-Export 'DHCP reservations' {
    Get-DhcpServerv4Scope -ComputerName $DhcpServer | ForEach-Object {
        Get-DhcpServerv4Reservation -ComputerName $DhcpServer -ScopeId $_.ScopeId
    } | Select-Object ScopeId, IPAddress, ClientId, Name, Description |
        Sort-Object ScopeId, IPAddress | Save-Csv -Name 'dhcp-reservations.csv'
}

Invoke-Export 'DHCP failover' {
    Get-DhcpServerv4Failover -ComputerName $DhcpServer |
        Select-Object Name, PrimaryServerName, SecondaryServerName, Mode, ReservePercent,
                      MaxClientLeadTime, StateSwitchInterval, State |
        Save-Csv -Name 'dhcp-failover.csv'
}

# ---------------- DNS ----------------
Invoke-Export 'DNS zones' {
    Get-DnsServerZone -ComputerName $DnsServer |
        Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate |
        Sort-Object ZoneName | Save-Csv -Name 'dns-zones.csv'
}

Invoke-Export 'DNS forwarders' {
    Get-DnsServerForwarder -ComputerName $DnsServer |
        Select-Object @{ n = 'Forwarders'; e = { $_.IPAddress -join ';' } }, UseRootHint, Timeout |
        Save-Csv -Name 'dns-forwarders.csv'
}

# ---------------- Active Directory ----------------
Invoke-Export 'AD organizational units' {
    Get-ADOrganizationalUnit -Filter * |
        Select-Object Name, DistinguishedName, ProtectedFromAccidentalDeletion |
        Sort-Object DistinguishedName | Save-Csv -Name 'ad-ous.csv'
}

Invoke-Export 'AD groups' {
    Get-ADGroup -Filter * -Properties Description |
        Select-Object Name, GroupScope, GroupCategory, Description, DistinguishedName |
        Sort-Object DistinguishedName | Save-Csv -Name 'ad-groups.csv'
}

Invoke-Export 'AD group memberships (lab OU)' {
    $domainDN = (Get-ADDomain).DistinguishedName
    Get-ADGroup -Filter * -SearchBase "OU=$LabOU,$domainDN" | ForEach-Object {
        $group = $_.Name
        Get-ADGroupMember -Identity $_ | ForEach-Object {
            [pscustomobject]@{ Group = $group; Member = $_.SamAccountName; MemberType = $_.objectClass }
        }
    } | Sort-Object Group, Member | Save-Csv -Name 'ad-group-members.csv'
}

Invoke-Export 'AD users (no password data)' {
    Get-ADUser -Filter * -Properties Department, Description |
        Select-Object SamAccountName, Name, Enabled, Department, Description, DistinguishedName |
        Sort-Object SamAccountName | Save-Csv -Name 'ad-users.csv'
}

Invoke-Export 'AD domain controllers' {
    Get-ADDomainController -Filter * |
        Select-Object Name, IPv4Address, Site, IsGlobalCatalog, OperatingSystem,
                      @{ n = 'Roles'; e = { $_.OperationMasterRoles -join ';' } } |
        Sort-Object Name | Save-Csv -Name 'ad-domain-controllers.csv'
}

# ---------------- Group Policy ----------------
Invoke-Export 'GPO reports (HTML)' {
    $dir = Join-Path $OutputPath 'gpo-reports'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Get-GPO -All | ForEach-Object {
        $safe = ($_.DisplayName -replace '[\\/:*?"<>|]', '_')
        Get-GPOReport -Guid $_.Id -ReportType Html -Path (Join-Path $dir "$safe.html")
    }
}

if ($IncludeGpoBackups) {
    Invoke-Export 'GPO backups (REVIEW BEFORE COMMITTING)' {
        $dir = Join-Path $OutputPath 'gpo-backups'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Backup-GPO -All -Path $dir | Out-Null
    }
}

# ---------------- Per-server roles and features ----------------
foreach ($server in ($Servers | Where-Object { -not ($SkipHyperV -and $_ -eq $HyperVHost) })) {
    Invoke-Export "Windows features on $server" {
        Get-WindowsFeature -ComputerName $server |
            Where-Object Installed |
            Select-Object Name, DisplayName |
            Save-Csv -Name ('{0}-features.csv' -f $server.ToLower())
    }
}

# ---------------- Hyper-V ----------------
if (-not $SkipHyperV) {
    Invoke-Export "Hyper-V VMs on $HyperVHost" {
        Get-VM -ComputerName $HyperVHost |
            Select-Object Name, Generation, ProcessorCount,
                          @{ n = 'StartupMemoryGB'; e = { [math]::Round($_.MemoryStartup / 1GB, 1) } },
                          DynamicMemoryEnabled, AutomaticStartAction, AutomaticStartDelay, CheckpointType |
            Sort-Object Name | Save-Csv -Name 'hyperv-vms.csv'
    }

    Invoke-Export "Hyper-V VM network/VLAN on $HyperVHost" {
        Get-VMNetworkAdapterVlan -VMName * -ComputerName $HyperVHost |
            Select-Object @{ n = 'VMName'; e = { $_.ParentAdapter.VMName } }, OperationMode, AccessVlanId |
            Sort-Object VMName | Save-Csv -Name 'hyperv-vm-vlans.csv'
    }
}

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Cyan
Write-Host '  1. git status && git diff     (review every change, look for anything sensitive)'
Write-Host '  2. git add configs && git commit -m "configs: refresh exports"'
Write-Host '  3. Add a line to CHANGELOG.md if the diff shows a real change'
