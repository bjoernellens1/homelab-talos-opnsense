# Hardware Layout & Role Mapping

This document details the physical hardware used in the homelab and its logical mapping to Kubernetes roles.

## Core Infrastructure

### Network Gateway: Topton Mini Firewall
- **Role**: OPNsense Router/Firewall, DNS, WoL Gateway
- **CPU**: Intel N100 (4 Cores)
- **RAM**: 32 GB
- **Networking**: 6x 2.5Gb Intel i226-V NICs
- **IP**: 10.10.0.1 (LAN) / 10.1.10.2 (WAN)

### Cluster Core: 3x Fujitsu Esprimo (Always On)
- **Role**: Talos Control Plane, Longhorn Storage, Core Services
- **CPU**: Intel(R) Core(TM) i5-7400T @ 2.40GHz
- **RAM**: 64 GB per node
- **Storage**:
    - 250 GB NVMe (Talos OS)
    - 2x 1 TB SATA SSD (Longhorn Distributed Storage)
- **Networking**:
    - 1x Internal 1Gb Intel NIC
    - 1x USB Realtek 2.5Gb NIC

### Cluster Edge: 2x Minisforum Mini PC (Intermittent)
- **Role**: Jellyfin, Media Automation, Burst Compute
- **CPU**: Intel N100 (4 Cores)
- **RAM**: 8 GB per node
- **Storage**: 250 GB NVMe (Talos OS)
- **Networking**: 2x 2.5Gb Intel NICs

## Storage & Backup

### Backup Target: WD MyCloud Home
- **Role**: NFS/S3 Backup for Longhorn
- **OS**: Debian with OpenMediaVault (flashed)
- **Storage**: 8 TB HDD
- **Networking**: 1Gb NIC

### Peripheral Gear
- **Fritzbox 7530AX**: DSL Modem & Wi-Fi Access Point
- **USB 3.0 RAID Enclosure**: 2nd HDD slot (Unused)

## Role Mapping Summary

| Hostname | Role | Zone | Availability |
|----------|------|------|--------------|
| `talos-core-01` | Control Plane | Core | Always On |
| `talos-core-02` | Control Plane | Core | Always On |
| `talos-core-03` | Control Plane | Core | Always On |
| `talos-edge-01` | Worker (Media) | Edge | Intermittent |
| `talos-edge-02` | Worker (Media) | Edge | Intermittent |
