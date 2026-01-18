# Homelab Talos-OPNsense

A production-ready homelab Kubernetes cluster built on Talos Linux with OPNsense networking, Fleet GitOps, and Longhorn storage.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     OPNsense Gateway                        │
│             10.10.0.1 - Split DNS & WoL                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
         ┌──────────────┴───────────────┐
         │ (10.10.0.0/24)               │
┌────────▼───────┐              ┌───────▼────────┐
│  Core Nodes    │              │   Edge Nodes   │
│   (Always On)  │              │  (Intermittent)│
├────────────────┤              ├────────────────┤
│ 3× Fujitsu     │              │ 2× Minisforum  │
│    Esprimo     │              │    N100        │
│ (Control Plane)│              │ (Tainted)      │
│ (Longhorn)     │              │                │
└────────────────┘              └────────────────┘
```

### Components

- **Talos Linux**: Immutable, API-managed Kubernetes OS
- **Upstream Kubernetes**: Vanilla K8s (no k3s)
- **Fleet GitOps**: Continuous delivery from Git to cluster
- **Longhorn Storage**: Distributed block storage (replicas=2, core nodes only)
- **OPNsense**: Network router/firewall (Topton N100) with split DNS
- **Wake-on-LAN**: HTTP gateway for on-demand edge node management

## Quick Start

### Prerequisites

- Talos Linux bootable nodes (core: 3 nodes, edge: 2 nodes)
- OPNsense firewall/router configured (Topton N100)
- `talosctl` CLI installed
- `kubectl` CLI installed
- Network: 10.10.0.0/24 subnet (behind OPNsense)

### 1. Configure Inventory

Edit `inventory/nodes.yaml` with your actual node IPs and MAC addresses.

### 2. Generate Talos Configurations

```bash
cd talos
./generate.sh
```

This creates:
- `secrets.yaml` - Cluster secrets (gitignored)
- `controlplane-*.yaml` - Control plane configs
- `worker-*.yaml` - Worker node configs
- `talosconfig` - CLI configuration
- `kubeconfig` - Kubernetes access

### 3. Apply Configurations to Nodes

For each node, apply its configuration:

```bash
# Control plane nodes (Fujitsu Esprimo)
talosctl apply-config --insecure --nodes 10.10.0.11 --file controlplane-talos-core-01.yaml
talosctl apply-config --insecure --nodes 10.10.0.12 --file controlplane-talos-core-02.yaml
talosctl apply-config --insecure --nodes 10.10.0.13 --file controlplane-talos-core-03.yaml

# Edge worker nodes (Minisforum N100)
talosctl apply-config --insecure --nodes 10.10.0.21 --file worker-talos-edge-01.yaml
talosctl apply-config --insecure --nodes 10.10.0.22 --file worker-talos-edge-02.yaml
```

### 4. Bootstrap Cluster

```bash
cd talos
./bootstrap.sh
```

This initializes the control plane and retrieves the kubeconfig.

### 5. Deploy Fleet GitOps

```bash
# Install Fleet
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm install fleet-crd fleet/fleet-crd -n cattle-fleet-system --create-namespace
helm install fleet fleet/fleet -n cattle-fleet-system

# Register this repository with Fleet
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab
  namespace: fleet-default
spec:
  repo: https://github.com/bjoernellens1/homelab-talos-opnsense
  branch: main
  paths:
  - fleet
EOF
```

### 6. Deploy Bundles

Fleet will automatically deploy bundles in order:
1. **Platform** - CNI (Cilium), Ingress (NGINX), cert-manager
2. **Storage** - Longhorn (core nodes, replicas=2)
3. **Core Services** - Always-on services
4. **Edge Services** - On-demand workloads
5. **Ops** - Monitoring (Prometheus, Grafana, Loki)

Monitor deployment:
```bash
kubectl get pods -A
kubectl get gitrepo -A
```

## Node Management

### Core Nodes

Core nodes are always-on (Fujitsu Esprimo) and host:
- Kubernetes control plane (3 nodes)
- Longhorn storage (Replicated across 3 nodes)
- Critical services
- Monitoring and logging

Labels:
- `node-role: core`
- `availability: always-on`
- `storage: longhorn`

### Edge Nodes

Edge nodes are on-demand (Minisforum N100) via Wake-on-LAN:
- Started via WoL gateway
- Tainted to prevent regular workload scheduling
- Power off when idle

Labels:
- `node-role: edge`
- `availability: intermittent`

Taints:
- `edge=true:NoSchedule`

#### Wake Edge Nodes

```bash
# Wake specific node
./scripts/wake-edge-nodes.sh talos-edge-01

# Wake all edge nodes
./scripts/wake-edge-nodes.sh all
```

#### Deploy WoL Gateway

```bash
kubectl apply -f scripts/wol-gateway.yaml
```

Access via HTTP API:
```bash
curl -X POST http://wol-gateway.wol-gateway:8080/wake/talos-edge-01
```

## Storage

### Longhorn Configuration

- **Replicas**: 2 (for redundancy with 2 storage nodes)
- **Node Selection**: Core nodes only (`storage-node: "true"`)
- **No ZFS/RAID**: Longhorn handles replication
- **Storage Classes**:
  - `longhorn` (default): Standard workloads
  - `longhorn-critical`: Retain policy, best-effort locality

Access Longhorn UI:
```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

Visit: http://localhost:8080

## Networking

### OPNsense Split DNS

OPNsense provides DNS resolution for:
- Internal: `*.cluster.local`, `*.homelab` → Local IPs
- External: `*.com`, `*.org` → Upstream DNS

See [`docs/opnsense-split-dns.md`](docs/opnsense-split-dns.md) for detailed configuration.

### Cluster Network

- **Subnet**: 10.10.0.0/24
- **Gateway**: 10.10.0.1 (OPNsense)
- **DNS**: 10.10.0.1 (OPNsense Unbound)
- **Cluster VIP**: 10.10.0.10 (Kubernetes API)

## Energy Management

### Power Optimization

- **Core nodes**: Always-on, performance-optimized
- **Edge nodes**: On-demand, energy-optimized
- **Estimated savings**: ~54 kWh/month

See [`docs/energy-tuning.md`](docs/energy-tuning.md) for:
- Wake-on-LAN setup
- CPU power management
- Automated wake/sleep schedules
- Energy monitoring with Prometheus

## Fleet Bundles

### Bundle Structure

```
fleet/
├── platform/          # CNI, Ingress, Cert-Manager
├── storage/           # Longhorn (core-only)
├── core-services/     # Always-on services
├── edge-services/     # On-demand workloads
└── ops/               # Monitoring & logging
```

### Customizing Bundles

Each bundle contains:
- `fleet.yaml` - Bundle metadata and targeting
- `manifests.yaml` - Kubernetes resources

Edit as needed and commit to Git. Fleet will auto-deploy changes.

## Monitoring

### Access Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Visit: http://localhost:3000
- Username: `admin`
- Password: `changeme` (change in production!)

### View Logs (Loki)

Logs are aggregated from all nodes (including edge when online).

Query via Grafana → Explore → Loki data source.

## Maintenance

### Update Talos

```bash
# Check current version
talosctl version --nodes 10.0.0.11

# Upgrade (example to v1.6.0)
talosctl upgrade --nodes 10.0.0.11 --image ghcr.io/siderolabs/installer:v1.6.0
```

### Update Kubernetes

```bash
# Upgrade Kubernetes version
talosctl upgrade-k8s --nodes 10.0.0.11 --to 1.29.0
```

### Backup etcd

```bash
talosctl -n 10.0.0.11 etcd snapshot etcd-backup.db
```

### Drain Node

```bash
kubectl drain talos-core-04 --ignore-daemonsets --delete-emptydir-data
```

## Troubleshooting

### Nodes Not Joining Cluster

```bash
# Check node status
talosctl -n 10.0.0.11 dmesg
talosctl -n 10.0.0.11 logs controller-runtime

# Check certificates
talosctl -n 10.0.0.11 get members
```

### Longhorn Volume Issues

```bash
# Check Longhorn health
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# Check volume status
kubectl get volumes -n longhorn-system
```

### Edge Nodes Won't Wake

1. Verify WoL enabled in BIOS
2. Check MAC address in `inventory/nodes.yaml`
3. Test manually: `wakeonlan -i 10.0.0.255 <MAC>`
4. Check OPNsense allows UDP port 9

See [`docs/energy-tuning.md`](docs/energy-tuning.md#troubleshooting) for more.

## Repository Structure

```
.
├── inventory/
│   └── nodes.yaml              # Node inventory (IPs, MACs, roles)
├── talos/
│   ├── patches/
│   │   ├── core.yaml           # Core node patches
│   │   └── edge.yaml           # Edge node patches
│   ├── generate.sh             # Generate Talos configs
│   └── bootstrap.sh            # Bootstrap cluster
├── fleet/
│   ├── platform/               # Platform bundle (CNI, Ingress)
│   ├── storage/                # Longhorn bundle
│   ├── core-services/          # Core services bundle
│   ├── edge-services/          # Edge services bundle
│   └── ops/                    # Monitoring bundle
├── scripts/
│   ├── wake-edge-nodes.sh      # WoL script
│   └── wol-gateway.yaml        # WoL gateway service
├── docs/
│   ├── opnsense-split-dns.md   # OPNsense DNS setup
│   └── energy-tuning.md        # Energy optimization guide
└── README.md
```

## Security Considerations

1. **Secrets**: Never commit `talos/secrets.yaml` or generated configs
2. **Network**: Firewall rules on OPNsense restrict access
3. **RBAC**: Configure Kubernetes RBAC for cluster access
4. **Updates**: Keep Talos and Kubernetes up-to-date
5. **Monitoring**: Enable audit logging and alerting

## Contributing

This is a personal homelab setup, but feel free to:
- Open issues for questions
- Submit PRs for improvements
- Use as a template for your own homelab

## License

MIT License - See LICENSE file

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
- [OPNsense Documentation](https://docs.opnsense.org/)

## Acknowledgments

Built with:
- Talos Linux by Sidero Labs
- Longhorn by SUSE Rancher
- Fleet by SUSE Rancher
- Cilium by Cilium.io
- OPNsense by Deciso