<#
.SYNOPSIS
    Creates a standardised Active Directory user with a random temporary password.

.DESCRIPTION
    - Builds the username as first initial + surname (e.g. jsmith), adding a number if taken.
    - Creates the user in the specified OU, enabled, with "change password at next logon" set.
    - Adds the user to the listed groups (warns if a group does not exist).
    - Prints the temporary password ONCE to the console. It is never written to disk.

    Requires the ActiveDirectory module and rights to create users in the target OU.

.PARAMETER GivenName
    First name.

.PARAMETER Surname
    Last name.

.PARAMETER Department
    Optional department, stored in the AD Department attribute.

.PARAMETER Groups
    Groups to add the user to. Defaults to GG-AllStaff.

.PARAMETER OU
    Distinguished name of the OU for the new user.

.PARAMETER Domain
    DNS domain name, used for the UserPrincipalName.

.EXAMPLE
    .\New-LabUser.ps1 -GivenName Jane -Surname Smith -Department Finance -Groups GG-AllStaff,GG-Finance

.EXAMPLE
    .\New-LabUser.ps1 -GivenName Jane -Surname Smith -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$GivenName,
    [Parameter(Mandatory)][string]$Surname,
    [string]$Department,
    [string[]]$Groups = @('GG-AllStaff'),
    [string]$OU = 'OU=Staff,OU=Users,OU=_Lab,DC=lab,DC=example,DC=com',
    [string]$Domain = 'lab.example.com'
)

Import-Module ActiveDirectory -ErrorAction Stop

function New-TempPassword {
    param([int]$Length = 16)
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*?'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        do {
            $bytes = New-Object byte[] $Length
            $rng.GetBytes($bytes)
            $password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
            # Require at least one of each class so it always meets domain complexity
            $ok = ($password -cmatch '[A-Z]') -and ($password -cmatch '[a-z]') -and
                  ($password -match '\d') -and ($password -match '[!@#$%&*?]')
        } until ($ok)
    }
    finally { $rng.Dispose() }
    return $password
}

# Build a unique username: first initial + surname, lowercase, letters/digits only, max 20 chars
$base = ($GivenName.Substring(0, 1) + $Surname).ToLower() -replace '[^a-z0-9]', ''
if ($base.Length -gt 18) { $base = $base.Substring(0, 18) }
$sam = $base
$n = 1
while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
    $n++
    $sam = "$base$n"
}

$displayName = "$GivenName $Surname"
$upn = "$sam@$Domain"
$tempPassword = New-TempPassword

if ($PSCmdlet.ShouldProcess("$sam ($displayName) in $OU", 'Create AD user')) {
    $params = @{
        Name                  = $displayName
        GivenName             = $GivenName
        Surname               = $Surname
        DisplayName           = $displayName
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Path                  = $OU
        AccountPassword       = (ConvertTo-SecureString $tempPassword -AsPlainText -Force)
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }
    if ($Department) { $params['Department'] = $Department }

    New-ADUser @params
    Write-Host "Created $sam ($upn)" -ForegroundColor Green

    foreach ($group in $Groups) {
        if (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $group -Members $sam
            Write-Host "  added to $group"
        }
        else {
            Write-Warning "  group '$group' not found, skipped"
        }
    }

    Write-Host ''
    Write-Host "Temporary password (shown once, user must change it at first logon):" -ForegroundColor Yellow
    Write-Host "  $tempPassword"
    Write-Host 'Give it to the user separately from the username. Do not paste it into chat, tickets, or this repo.'
}
