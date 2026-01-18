## NETWORK WALKTHROUGH — AUTHORITATIVE DESIGN (FOR CODE AGENT)

### Objective

Integrate a Kubernetes cluster behind **OPNsense** while keeping an existing **Fritzbox Wi-Fi network (10.1.10.0/24)** fully functional.
Wi-Fi clients (e.g. FireTV) must access **internal services (Jellyfin, OpenCloud)** directly via **split DNS**, without internet hairpinning or port forwarding.

---

## Network Addressing (Fixed Decisions)

### Existing Network

* Fritzbox LAN + Wi-Fi:

  ```
  10.1.10.0/24
  Fritzbox IP: 10.1.10.1
  ```

### New Internal Network (OPNsense LAN)

* Dedicated routed subnet:

  ```
  10.10.0.0/24
  OPNsense LAN IP: 10.10.0.1
  ```

### Key Static IPs

* OPNsense WAN: `10.1.10.2`
* Kubernetes control-plane VIP: `10.10.0.10`
* Core nodes: `10.10.0.11–13`
* Edge nodes: `10.10.0.21–22`
* Kubernetes ingress / LB: `10.10.0.50`
* WoL gateway (optional): `10.10.0.60`

---

## Physical & Logical Topology

```
Internet
  |
[Fritzbox 7530AX]
  |  LAN/Wi-Fi 10.1.10.0/24
  |
  +--> OPNsense (WAN: 10.1.10.2)
         |
         |  LAN 10.10.0.0/24
         +--> Kubernetes nodes
         +--> Storage
```

### Role Separation

* **Fritzbox**

  * DSL modem
  * Wi-Fi access point
  * Default NAT to internet
* **OPNsense**

  * Router between 10.1.10.0/24 and 10.10.0.0/24
  * Firewall
  * DNS (Unbound)
  * Default gateway for cluster

---

## Required Configuration (Mandatory)

### 1. Static Route on Fritzbox

Fritzbox must know how to reach the Kubernetes subnet.

**Configure in Fritzbox UI → Network → Routing → Static Routes:**

```
Destination: 10.10.0.0
Netmask:     255.255.255.0
Gateway:     10.1.10.2   (OPNsense WAN)
```

This enables Wi-Fi clients to reach services behind OPNsense.

---

### 2. Firewall Rules on OPNsense

Allow routed traffic from Fritzbox LAN to cluster LAN.

On **OPNsense WAN interface**:

* Allow:

  * Source: `10.1.10.0/24`
  * Destination: `10.10.0.0/24`
  * Ports: `80`, `443` (plus others as required)
* No NAT
* Stateful routing only

---

## DNS Architecture (Split DNS — Required)

### Principle

All clients (including Fritzbox Wi-Fi clients) must resolve **internal service names** via **OPNsense Unbound**, not public DNS.

### DNS Flow

```
Client (Wi-Fi)
 → DNS query jellyfin.home.arpa
 → OPNsense Unbound
 → returns 10.10.0.50
 → client connects directly via routed LAN path
```

### Fritzbox DNS Configuration

Set Fritzbox to forward DNS queries to OPNsense:

```
Primary DNS: 10.1.10.2
Secondary:   (unset)
```

Ensure Unbound listens on:

* OPNsense LAN
* OPNsense WAN (10.1.10.2)

---

### Unbound Internal Zone

Create internal zone:

```
home.arpa
```

Host overrides:

```
jellyfin.home.arpa   → 10.10.0.50
opencloud.home.arpa  → 10.10.0.50
wol.home.arpa        → 10.10.0.60
```

Ingress inside Kubernetes handles service routing.

---

## Client Traffic Examples

### Wi-Fi Client → Jellyfin

1. FireTV gets IP `10.1.10.x`
2. DNS lookup `jellyfin.home.arpa`
3. OPNsense returns `10.10.0.50`
4. Traffic flows:

   ```
   FireTV → Fritzbox → OPNsense → Kubernetes ingress → Jellyfin
   ```
5. No NAT, no internet traversal

### Kubernetes → Internet

```
Pod → OPNsense → Fritzbox → Internet
```

NAT happens only on Fritzbox.

---

## Energy & Simplicity Considerations

* Only one NAT device (Fritzbox)
* OPNsense does pure routing + DNS
* No IDS/IPS unless explicitly enabled
* No VLANs required
* Routing two /24 networks is negligible CPU load on N100

---

## Explicit Non-Goals

* No port forwarding
* No hairpin NAT
* No public DNS for internal services
* No overlapping subnets

---

## Implementation Note for Repo

Document this network setup in:

```
docs/01-networking-opnsense-fritzbox.md
opnsense/dhcp-dns/unbound-overrides.md
opnsense/firewall-rules.md
```

This network design is **final and authoritative**.
All automation and documentation must assume this topology.
