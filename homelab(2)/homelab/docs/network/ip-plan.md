# IP Plan

*(All addresses are examples. Replace with your own.)*

## Conventions

- `.1` is always the gateway.
- `.2`-`.9`: network gear.
- `.10`-`.99`: static infrastructure.
- `.100`-`.199`: DHCP pool (client VLANs only).
- `.200`-`.254`: reserved for future use / temporary static.

## VLAN 10: Management (10.0.10.0/24)

| IP | Hostname | Device | Notes |
|---|---|---|---|
| 10.0.10.1 | gw | Router / firewall | Gateway |
| 10.0.10.2 | sw01 | Managed switch | Admin interface |
| 10.0.10.3 | ap01 | Wi-Fi access point | |
| 10.0.10.10 | HV01 | Hyper-V host (management OS) | Static |
| 10.0.10.20 | NAS01 | Backup target | Static |
| 10.0.10.50 | ADMIN-PC | Admin workstation | Reservation |

## VLAN 20: Servers (10.0.20.0/24)

| IP | Hostname | Role | Notes |
|---|---|---|---|
| 10.0.20.1 | gw | Gateway | |
| 10.0.20.10 | DC01 | Domain controller, DNS, DHCP | Primary DNS for all hosts |
| 10.0.20.11 | DC02 | Domain controller, DNS, DHCP | Secondary DNS for all hosts |
| 10.0.20.20 | FILE01 | File server | |
| 10.0.20.30-.39 | | Reserved for future member servers | e.g. CA, WSUS, WAC |

## VLAN 30: Clients (10.0.30.0/24)

| IP / Range | Purpose | Notes |
|---|---|---|
| 10.0.30.1 | Gateway | |
| 10.0.30.100-.199 | DHCP pool | Served by DC01/DC02 failover |
| 10.0.30.20-.29 | DHCP reservations | Printers, test clients that need stable IPs |

## VLAN 40: Guest / IoT (10.0.40.0/24)

| IP / Range | Purpose | Notes |
|---|---|---|
| 10.0.40.1 | Gateway | Also serves DHCP (router) |
| 10.0.40.100-.199 | DHCP pool | Served by router, **not** by the domain DHCP servers |

## DNS settings on every domain-joined machine

| Setting | Value |
|---|---|
| Primary DNS | 10.0.20.10 (DC01) |
| Secondary DNS | 10.0.20.11 (DC02) |
| Search suffix | `lab.example.com` *(example)* |

On the domain controllers themselves: DC01 uses DC02 as primary and itself as secondary, and DC02 does the reverse. Avoid pointing a DC only at itself.
