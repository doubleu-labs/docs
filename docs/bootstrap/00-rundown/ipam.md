# IPAM

The DoubleU Labs network uses 12 virtual LANs (VLANs) to logically organize
networks and provide isolation when required.

All networks are under the class A reserved IPv4 range (`10.0.0.0/8`).

The purpose of this documentation is to track static IP address assignments
during the stand-up process.

The OPNSense firewall routes on the native VLAN as well as the IoT, Wireguard,
and the isolated Untrusted Client VLANs.

All other VLANS are only routed on the switches. These VLANS omit assignment of
IP address `10.0.X.1` for consistency and organizational purposes.

The Out-of-Band Management VLAN only exists on the PCT6248 access switch and is
not accessible from other VLANs for security purposes.

## `10.0.0.0/24` - Native

- Untagged VLAN # `1`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| `10.0.0.1`    | Gateway (FIREWALL)    |
| `10.0.0.2`    | Gateway (PSS4810)     |
| `10.0.0.3`    | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.0.10`   | DNS01                 |
| `10.0.0.11`   | DNS02                 |
| `10.0.0.12`   | NETBOX                |
| `10.0.0.13`   | CA                    |
| `10.0.0.14`   | KEYCLOAK              |
| /             | /                     |

## `10.0.1.0/24` - Out-of-Band Management

- Tagged VLAN # `1000`
- :x: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.1.10`   | UPS                   |
| /             | /                     |
| `10.0.1.20`   | iDRAC FIREWALL        |
| `10.0.1.21`   | PSS4810               |
| `10.0.1.22`   | PCT6248               |
| /             | /                     |
| `10.0.1.30`   | iDRAC TNS01           |
| `10.0.1.31`   | iDRAC TNS02           |
| `10.0.1.32`   | iDRAC BTNS01          |
| /             | /                     |
| `10.0.1.40`   | iDRAC XCP01           |
| /             | /                     |

## `10.0.2.0/24` - In-Band Management

- Tagged VLAN # `2`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.2.2`    | Gateway (PSS4810)     |
| `10.0.2.3`    | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.2.9`    | IPKVM                 |
| `10.0.2.10`   | CRITICLUSTER01        |
| `10.0.2.11`   | CRITICLUSTER02        |
| `10.0.2.12`   | CRITICLUSTER03        |
| /             | /                     |
| `10.0.2.20`   | TNS01                 |
| `10.0.2.21`   | TNS02                 |
| `10.0.2.22`   | BTNS01                |
| /             | /                     |
| `10.0.2.30`   | XCP01                 |
| /             | /                     |
| `10.0.2.200`  | UNIFI                 |
| `10.0.2.210`  | NORTHCOM (AP)         |
| `10.0.2.211`  | SOUTHCOM (AP)         |
| /             | /                     |


## `10.0.3.0/24` - Services

- Tagged VLAN # `3`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.3.2`    | Gateway (PSS4810)     |
| `10.0.3.3`    | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.3.10`   | PLEX                  |
| `10.0.3.11`   | SONARR                |
| `10.0.3.12`   | RADARR                |
| `10.0.3.13`   | GIT                   |
| /             | /                     |

## `10.0.10.0/24` - Active Directory Servers

- Tagged VLAN # `10`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.10.2`   | Gateway (PSS4810)     |
| `10.0.10.3`   | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.10.10`  | DC01                  |
| `10.0.10.11`  | DC02                  |
| `10.0.10.12`  | PKI                   |
| `10.0.10.13`  | DCHP                  |
| /             | /                     |

## `10.0.11.0/24` - Active Directory Clients

- Tagged VLAN # `11`
- :white_check_mark: Routed
- :white_check_mark: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.11.2`   | Gateway (PSS4810)     |
| `10.0.11.3`   | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.11.10`  | ( DCHP Start )        |
| -             | -                     |
| `10.0.11.250` | ( DHCP End )          |
| /             | /                     |

## `10.0.20.0/24` - IdM Servers

- Tagged VLAN # `20`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.20.2`   | Gateway (PSS4810)     |
| `10.0.20.3`   | Gateway (PCT6248)     |

## `10.0.21.0/24` IdM Clients

- Tagged VLAN # `21`
- :white_check_mark: Routed
- :white_check_mark: DHCP

| Address       | Description           |
| :-            | :-                    |
| /             | /                     |
| `10.0.21.2`   | Gateway (PSS4810)     |
| `10.0.21.3`   | Gateway (PCT6248)     |
| /             | /                     |
| `10.0.21.10`  | ( DCHP Start )        |
| -             | -                     |
| `10.0.21.250` | ( DHCP End )          |
| /             | /                     |

## `10.0.100.0/24` - Trusted Clients

- Tagged VLAN # `100`
- :white_check_mark: Routed
- :white_check_mark: DHCP

| Address           | Description           |
| :-                | :-                    |
| `10.0.100.1`      | Gateway (FIREWALL)    |
| `10.0.100.2`      | Gateway (PSS4810)     |
| `10.0.100.3`      | Gateway (PCT6248)     |
| /                 | /                     |
| `10.0.100.10`     | ( DCHP Start )        |
| -                 | -                     |
| `10.0.100.250`    | ( DHCP End )          |
| /                 | /                     |

## `10.0.101.0/24` - Wireguard Clients

- Tagged VLAN # `101`
- :white_check_mark: Routed
- :x: DHCP

| Address       | Description           |
| :-            | :-                    |
| `10.0.101.1`  | Gateway (FIREWALL)    |
| `10.0.101.2`  | Gateway (PSS4810)     |
| `10.0.101.3`  | Gateway (PCT6248)     |
| /             | /                     |

## `10.0.107.0/24` - Internet of Trash

- Tagged VLAN # `107`
- :white_check_mark: Routed
- :white_check_mark: DHCP

| Address           | Description           |
| :-                | :-                    |
| `10.0.107.1`      | Gateway (FIREWALL)    |
| `10.0.107.2`      | Gateway (PSS4810)     |
| `10.0.107.3`      | Gateway (PCT6248)     |
| /                 | /                     |
| `10.0.107.10`     | ( DCHP Start )        |
| -                 | -                     |
| `10.0.107.250`    | ( DHCP End )          |
| /                 | /                     |

## `10.0.254.0/24` - Untrusted Clients

- Tagged VLAN # `254`
- :x: Routed
- :white_check_mark: DHCP

| Address           | Description           |
| :-                | :-                    |
| `10.0.254.1`      | Gateway (FIREWALL)    |
| /                 | /                     |
| `10.0.254.10`     | ( DCHP Start )        |
| -                 | -                     |
| `10.0.254.250`    | ( DHCP End )          |
| /                 | /                     |

