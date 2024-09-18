# Hardware

This is the current list of hardware comprising the DoubleU Labs Homelab:

- 1x - Dell PowerSwitch S4810
- 1x - Dell PowerConnect 6248
- 1x - Dell PowerEdge R630 8-bay
- 1x - Dell PowerEdge R630 10-bay
- 1x - Dell PowerEdge R730xd LFF
- 2x - Dell PowerEdge R730xd SFF
- 3x - Raspberry Pi 4B 8GB
- 1x - Dell DMPU4023 IPKVM w/ DKMMLED185

## Firewall

The following server hosts OPNSense for firewall and router duties:

- Dell PowerEdge R630 8-bay
    - 1x Intel Xeon E5-2630 v4
    - 8x DDR4-2133 ECC REG (64GB Total)
    - Intel X520/i350 OCP 2.0 Mezzanine NIC
        - X520-DA2 Dual SFP+ 10Gb
        - i350-T2 Dual 1GbE

One of the i350 interfaces is used for WAN connectivity. The two SFP+ ports are
aggregated down to the S4810 switch.

The firewall provides DHCP services for dedicated client subnets, as well as
Wireguard endpoints for VPN access to the Lab network.

## CritiCluster

The three `Raspberry Pi 4B 8GB` run Fedora CoreOS and host a K3s Kubernetets
cluster to provide critical network services, such as Domain Name Services
(DNS), IP Address Management (IPAM), Certificate Authority (CA), Single Sign-On 
(SSO), and VM Server Management (Xen Orchestra).

Each Raspberry Pi is equipped with an SPI Real Time Clock (RTC) and a 1TB SSD
over USB3.

The RTC is critical for Kubernetes operation. When the system boots without one
installed, it believes the current time is the timestamp of when the system was
installed, resulting in certificate errors when K3s attempts to start
(certificate `ValidFrom` dates will be in the future).

## Storage

### Media

The following server runs TrueNAS SCALE and is dedicated to local media
streaming via Plex:

- Dell PowerEdge R730xd LFF
    - 2x Intel Xeon E5-2690 V4
    - 8x DDR4-2133 ECC REG (64GB Total)
    - Intel X710-DA4 OCP 2.0 Mezzanine NIC, Quad SFP+ 10Gb
    - Intel Arc A380 GPU
    - Asus Hyper M.2 X16, Quad NVMe Adapter
        - 2x NVMe SSD, 1TB

The two NVMe drives are a mirrored pool for App storage. The Arc A380 is passed
through to a Plex instance for hardware transcoding.

The four SFP+ ports are aggregated to the S4810 core switch.

### Data

The primary data server runs TrueNAS SCALE and primarly serves SMB and NFS
storage, as well as Minio S3 and Gitea services.

- Dell PowerEdge R730xd SFF
    - 2x Intel Xeon E5-2690 V4
    - 8x DDR4-2133 ECC REG (64GB Total)
    - Intel X710-DA4 OCP 2.0 Mezzanine NIC, Quad SFP+ 10Gb
    - Asus Hyper M.2 X16, Quad NVMe Adapter
        - 2x NVMe SSD, 1TB

The two NVMe drives are a mirrored pool for App storage.

The four SFP+ ports are aggregated to the S4810 core switch.

### Backup

The backup server runs TrueNAS SCALE and its sole purpose is to recieve ZFS
snapshots from the primary data server.

- Dell PowerEdge R730xd SFF
    - 2x Intel Xeon E5-2690 V4
    - 8x DDR4-2133 ECC REG (64GB Total)
    - Intel X710-DA4 OCP 2.0 Mezzanine NIC, Quad SFP+ 10Gb

This server then uploads to Backblaze for off-site backup storage.

## Virtualization

The virtualization host runs XCP-ng and is managed from Xen Orchestra hosted on
the CritiCluster.

- Dell PowerEdge R630 10-bay
    - 2x Intel Xeon E5-2690 V4
    - 8x DDR4-2133 ECC REG (64GB Total)
    - Intel X710-DA4 OCP 2.0 Mezzanine NIC, Quad SFP+ 10Gb

The plan is to expand virtualization across two additional servers for a three
host cluster.

The purpose of this cluster is to host Microsoft Windows Active Directory,
RedHat IdM, and an OpenShift (OKD) cluster for applications.

## Management

Each server is equiped with iDRAC Enterprise licenses, so hardware management of
the Dell servers is done when connected to the isolated out-of-band managment
VLAN.

The DMPU4032 IPKVM also provides interactive management from the network.