# DNS and DHCP

| | |
|---|---|
| **DNS servers** | DC01 (10.0.20.10), DC02 (10.0.20.11) |
| **DHCP servers** | DC01, DC02, in a failover relationship |
| **Last reviewed** | 2026-11-03 |

## DNS

### Zones

| Zone | Type | Replication | Dynamic updates |
|---|---|---|---|
| `lab.example.com` | Primary, AD-integrated | All DNS servers in the domain | Secure only |
| `_msdcs.lab.example.com` | Primary, AD-integrated | All DNS servers in the forest | Secure only |
| `20.0.10.in-addr.arpa` | Reverse lookup, AD-integrated | All DNS servers in the domain | Secure only |
| `30.0.10.in-addr.arpa` | Reverse lookup, AD-integrated | All DNS servers in the domain | Secure only |

### Forwarders

| Server | Forwarders |
|---|---|
| DC01, DC02 | `<UPSTREAM DNS 1>`, `<UPSTREAM DNS 2>` (e.g. router, 1.1.1.1, 9.9.9.9) |

```powershell
Set-DnsServerForwarder -IPAddress '<UPSTREAM DNS 1>','<UPSTREAM DNS 2>'
Get-DnsServerForwarder
```

### Scavenging

Stale records build up as DHCP clients come and go. Scavenging is enabled on **DC01 only**:

```powershell
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -ComputerName DC01
Set-DnsServerZoneAging -Name 'lab.example.com' -Aging $true -RefreshInterval 7.00:00:00 -NoRefreshInterval 7.00:00:00
```

### Useful checks

```powershell
Resolve-DnsName dc01.lab.example.com -Server 10.0.20.10
Resolve-DnsName _ldap._tcp.dc._msdcs.lab.example.com -Type SRV
Get-DnsServerZone | Select ZoneName, ZoneType, IsDsIntegrated, DynamicUpdate
dcdiag /test:dns /v
```

## DHCP

DHCP serves **VLAN 30 (Clients)** only. The router relays requests from VLAN 30 to both DCs ([topology](../network/topology.md#dhcp-relay)). Guest VLAN 40 is served by the router itself.

### Scopes

| Scope | Name | Range | Mask | Router | Lease |
|---|---|---|---|---|---|
| 10.0.30.0 | Clients | 10.0.30.100 - 10.0.30.199 | 255.255.255.0 | 10.0.30.1 | 8 days |

### Scope options

| Option | Value |
|---|---|
| 003 Router | 10.0.30.1 |
| 006 DNS Servers | 10.0.20.10, 10.0.20.11 |
| 015 DNS Domain Name | `lab.example.com` |

### Reservations

| Name | MAC | IP | Notes |
|---|---|---|---|
| `<DEVICE>` | `<MAC>` | 10.0.30.20 | Printer |

### Failover

| Setting | Value |
|---|---|
| Relationship name | `DC01-DC02` |
| Mode | Hot standby (DC01 active, DC02 standby) |
| Reserve address percentage | 5% |
| Max client lead time / state switch interval | 1 hour |

### Build commands

```powershell
# Authorise in AD (once per DHCP server)
Add-DhcpServerInDC -DnsName 'dc01.lab.example.com' -IPAddress 10.0.20.10
Add-DhcpServerInDC -DnsName 'dc02.lab.example.com' -IPAddress 10.0.20.11

# Scope on DC01
Add-DhcpServerv4Scope -Name 'Clients' -StartRange 10.0.30.100 -EndRange 10.0.30.199 `
    -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
Set-DhcpServerv4OptionValue -ScopeId 10.0.30.0 -Router 10.0.30.1 `
    -DnsServer 10.0.20.10,10.0.20.11 -DnsDomain 'lab.example.com'

# Failover to DC02
Add-DhcpServerv4Failover -ComputerName 'DC01' -PartnerServer 'DC02' -Name 'DC01-DC02' `
    -ScopeId 10.0.30.0 -ServerRole Active -ReservePercent 5 `
    -MaxClientLeadTime 01:00:00 -StateSwitchInterval 01:00:00
```

### Useful checks

```powershell
Get-DhcpServerv4Failover
Get-DhcpServerv4Scope | Select ScopeId, Name, StartRange, EndRange, State
Get-DhcpServerv4ScopeStatistics
Get-DhcpServerv4Lease -ScopeId 10.0.30.0 | Select IPAddress, HostName, ClientId, LeaseExpiryTime
```

## Known issues / notes

- Clients getting 169.254.x.x addresses: check the router's DHCP relay first, then the failover state.
