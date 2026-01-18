Below is a **clean, structured summary of the entire design discussion**, written as **context for a capable code agent** (Cursor / Copilot / Claude Code–style) that already understands Kubernetes, Talos, GitOps, etc.
This is **not instructions**, but **design intent + decisions**, to be used as long-term reference.

---

## Homelab Design Summary (Authoritative Context)

### Overall Goal

Build a **power-efficient, fully automated homelab** using **existing low-power hardware**, optimized for **Kubernetes-native operations**, minimal OS maintenance, and clear separation between **always-on core services** and **intermittent edge workloads** (media, downloads).

---

## Hardware Roles

### Network

* **Topton N100** runs **OPNsense**
* Fritzbox remains DSL modem + Wi-Fi AP
* Cluster lives *behind* OPNsense
* Clients on Fritzbox Wi-Fi must access services directly via **split DNS**, not via internet hairpin

### Kubernetes Nodes

* **Core nodes (always on)**:
  3× Fujitsu Esprimo thin clients

  * Idle ~5 W each
  * 250 GB NVMe (OS)
  * 2×1 TB SATA SSD (storage)

* **Edge nodes (intermittent)**:
  2× Minisforum N100

  * Can be powered off
  * Used for Jellyfin, media stack, burst compute

### Storage

* **Longhorn only**
* No ZFS, no mdraid
* OS disks: NVMe
* Longhorn disks: raw ext4/XFS on SATA SSDs
* Replica count = **2**
* Longhorn runs **only on core nodes**
* WD MyCloud (OMV) used for **backup target only** (NFS/S3)

---

## Operating System Choice

### Kubernetes OS

* **Talos Linux**
* Upstream Kubernetes (NOT k3s)
* Immutable, API-managed, minimal OS maintenance
* Nodes treated as cattle

### Rationale

* Avoid OS snowflakes
* Declarative lifecycle
* Easy node replacement
* Power efficiency comes from *workload placement*, not aggressive OS tuning

---

## Kubernetes Architecture

### Cluster

* 3-node control plane (Esprimos)
* Scheduling allowed on control planes
* No virtualization layer
* No Harvester (too heavy, unnecessary VM stack)

### GitOps

* **Fleet** (not Flux)
* Chosen for:

  * Rancher UI integration
  * Bundle-based deployment
  * Clear visibility
* Rancher UI may be:

  * Always-on **or**
  * On-demand / scaled down when not needed

---

## Core vs Edge Scheduling Model

### Core Nodes

* Labels:

  * `node-role=core`
  * `availability=always-on`
  * `storage=longhorn`
* Run:

  * Ingress
  * OpenCloud
  * Databases
  * Longhorn
  * WoL gateway
  * GitOps controllers

### Edge Nodes

* Labels:

  * `node-role=edge`
  * `availability=intermittent`
* Taint:

  * `edge=true:NoSchedule`
* Only workloads with explicit tolerations may run here
* Used for:

  * Jellyfin
  * Media automation
  * Transcoding
* No stateful or storage workloads

### Affinity Strategy

* Edge workloads use:

  * tolerations for edge taint
  * **preferred** affinity to edge
  * optional fallback to core (configurable)

---

## Wake-on-LAN Design (Critical)

### Problem

Kubernetes does not wake powered-off hardware. First request must hit something alive.

### Solution

Implement an **always-on WoL gateway** in core cluster:

* HTTP service
* Endpoint: `/wake?node=edge-01`
* Sends WoL magic packet
* Polls Kubernetes API for node readiness
* Once ready:

  * redirects or proxies to target service (e.g. Jellyfin)

### Result

* FireTV / clients never see “connection refused”
* Edge nodes wake **on demand**
* Clean UX

---

## Networking & DNS

### Split DNS (Mandatory)

* OPNsense runs **Unbound**
* Internal zone (e.g. `home.arpa`)
* Host overrides:

  * `jellyfin.home.arpa → internal ingress IP`
  * `opencloud.home.arpa → internal ingress IP`
* Fritzbox Wi-Fi clients use OPNsense as DNS

### Routing

* Prefer: Fritzbox as AP only
* Acceptable: Fritzbox NAT + static route + firewall rules

---

## Energy Efficiency Principles

### High Impact

* Keep node count minimal and predictable
* Edge nodes powered off when unused
* Avoid heavy IDS/IPS on OPNsense
* Avoid noisy monitoring stacks
* Avoid ZFS overhead

### Talos

* Minimal tuning
* Conservative sysctls only
* Power savings achieved via:

  * BIOS C-states
  * ASPM
  * workload scheduling

### OPNsense

* Adaptive powerd
* IDS disabled unless needed
* Reduced logging
* Disable unused NICs/services

---

## Repository Philosophy

The Git repo (`homelab-ops`) is:

* **Single source of truth**
* Inventory-driven
* Fully declarative
* GitOps-enforced
* Safe to rebuild cluster from scratch

Repo contains:

* Inventory
* Talos patches + rendered configs
* Fleet bundles (platform, storage, core, edge, ops)
* WoL gateway
* OPNsense documentation
* CI validation

---

## Explicit Non-Goals

* No VMs
* No Harvester
* No ZFS
* No k3s
* No always-on Rancher if unnecessary
* No manual snowflake configuration

---

**This summary represents final architectural intent.
All automation, manifests, and scripts should conform to it.**
