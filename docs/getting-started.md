# Getting Started Guide

Complete walkthrough for deploying your homelab Talos-OPNsense cluster.

## Prerequisites

### Hardware

**Core Nodes (5 required)**:
- 3× Control plane nodes: 4 CPU cores, 8 GB RAM, 100 GB disk
- 2× Worker nodes: 8 CPU cores, 16 GB RAM, 500 GB disk (for Longhorn)

**Edge Nodes (3 optional)**:
- 3× Worker nodes: 4 CPU cores, 8 GB RAM, 100 GB disk
- Must support Wake-on-LAN in BIOS

**Network**:
- OPNsense firewall/router
- Managed switch (for VLANs, optional)
- 10.0.0.0/16 network configured

### Software

Install these tools on your management workstation:

```bash
# Talos CLI
curl -sL https://talos.dev/install | sh

# Kubernetes CLI
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# wakeonlan (for edge nodes)
sudo apt-get install wakeonlan  # Ubuntu/Debian
brew install wakeonlan          # macOS
```

## Step 1: Prepare OPNsense

### 1.1 Configure Network

1. Navigate to **Interfaces → LAN**
2. Set IPv4 Configuration:
   - Type: Static IPv4
   - IPv4 Address: 10.0.0.1
   - Subnet Mask: 16 (10.0.0.0/16)

3. Enable DHCP (optional):
   - Navigate to **Services → DHCPv4 → LAN**
   - Enable DHCP server
   - Range: 10.0.0.100 - 10.0.0.200
   - Reserve IPs for cluster nodes (10.0.0.11-15, 10.0.1.21-23)

### 1.2 Configure DNS

Follow the complete guide in [`docs/opnsense-split-dns.md`](opnsense-split-dns.md).

Quick setup:
1. Navigate to **Services → Unbound DNS → General**
2. Enable Unbound DNS
3. Add host overrides for all cluster nodes
4. Configure upstream DNS (1.1.1.1, 8.8.8.8)

### 1.3 Enable Wake-on-LAN

1. Navigate to **Services → Wake on LAN**
2. Add entries for each edge node:
   - Interface: LAN
   - MAC: (from `inventory/nodes.yaml`)
   - Description: Node hostname

## Step 2: Install Talos Linux

### 2.1 Download Talos

Get the latest Talos ISO:
```bash
# Check latest version at https://github.com/siderolabs/talos/releases
VERSION="v1.6.0"
curl -LO https://github.com/siderolabs/talos/releases/download/${VERSION}/talos-amd64.iso
```

### 2.2 Create Bootable Media

```bash
# USB drive (replace /dev/sdX with your device)
sudo dd if=talos-amd64.iso of=/dev/sdX bs=4M status=progress
```

Or use Ventoy/Rufus for easier multi-boot.

### 2.3 Boot Nodes

1. Boot each node from Talos ISO/USB
2. Talos will:
   - Detect network (DHCP or wait for static config)
   - Start API server on port 50000
   - Wait for configuration

3. Note each node's IP address (displayed on console)

### 2.4 Alternative: Disk Image

For bare metal or VMs, install to disk:

```bash
# From Talos live environment
talosctl apply-config --insecure \
  --nodes <NODE_IP> \
  --file /path/to/config.yaml

# Or create disk image for cloning
talosctl image factory
```

## Step 3: Configure Inventory

Edit `inventory/nodes.yaml` with your actual values:

```yaml
core_nodes:
  - hostname: talos-core-01
    ip: 10.0.0.11          # YOUR actual IP
    mac: AA:BB:CC:DD:EE:01 # YOUR actual MAC
    # ...

edge_nodes:
  - hostname: talos-edge-01
    ip: 10.0.1.21          # YOUR actual IP
    mac: AA:BB:CC:DD:EE:11 # YOUR actual MAC
    # ...
```

Get MAC addresses:
```bash
# From node console
ip link show

# Or from OPNsense DHCP leases
# Navigate to Status → DHCP Leases
```

## Step 4: Generate Configurations

```bash
# From repository root
make generate-configs

# Or manually:
cd talos
./generate.sh
```

This creates:
- `talos/secrets.yaml` - Cluster PKI (keep secret!)
- `talos/controlplane-*.yaml` - Control plane configs
- `talos/worker-*.yaml` - Worker configs
- `talos/talosconfig` - Management CLI config
- `talos/kubeconfig` - Kubernetes access (after bootstrap)

## Step 5: Apply Configurations

### 5.1 Control Plane Nodes

```bash
export TALOSCONFIG=$(pwd)/talos/talosconfig

# Apply to each control plane node
talosctl apply-config --insecure \
  --nodes 10.0.0.11 \
  --file talos/controlplane-talos-core-01.yaml

talosctl apply-config --insecure \
  --nodes 10.0.0.12 \
  --file talos/controlplane-talos-core-02.yaml

talosctl apply-config --insecure \
  --nodes 10.0.0.13 \
  --file talos/controlplane-talos-core-03.yaml
```

Nodes will reboot and apply configuration.

### 5.2 Core Worker Nodes

```bash
talosctl apply-config --insecure \
  --nodes 10.0.0.14 \
  --file talos/worker-talos-core-04.yaml

talosctl apply-config --insecure \
  --nodes 10.0.0.15 \
  --file talos/worker-talos-core-05.yaml
```

### 5.3 Edge Worker Nodes

```bash
talosctl apply-config --insecure \
  --nodes 10.0.1.21 \
  --file talos/worker-talos-edge-01.yaml

talosctl apply-config --insecure \
  --nodes 10.0.1.22 \
  --file talos/worker-talos-edge-02.yaml

talosctl apply-config --insecure \
  --nodes 10.0.1.23 \
  --file talos/worker-talos-edge-03.yaml
```

## Step 6: Bootstrap Cluster

```bash
# Wait for nodes to be ready (check console or ping)
# Then bootstrap

make bootstrap

# Or manually:
cd talos
./bootstrap.sh
```

This will:
1. Bootstrap etcd on first control plane
2. Wait for Kubernetes API
3. Retrieve kubeconfig
4. Display cluster status

### Verify Bootstrap

```bash
export KUBECONFIG=$(pwd)/talos/kubeconfig

# Check nodes (may show NotReady - CNI not yet installed)
kubectl get nodes

# Check control plane pods
kubectl get pods -n kube-system
```

## Step 7: Deploy Fleet GitOps

```bash
make install-fleet

# Or manually:
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm repo update
helm install fleet-crd fleet/fleet-crd -n cattle-fleet-system --create-namespace
helm install fleet fleet/fleet -n cattle-fleet-system
```

### Register Git Repository

```bash
make register-gitrepo

# Or manually:
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
  targets:
  - clusterSelector:
      matchLabels:
        cluster: homelab
EOF

# Label cluster
CLUSTER_NAME=$(kubectl get clusters.fleet.cattle.io -n fleet-default -o jsonpath='{.items[0].metadata.name}')
kubectl label clusters.fleet.cattle.io -n fleet-default $CLUSTER_NAME cluster=homelab
```

## Step 8: Wait for Bundle Deployment

Fleet will automatically deploy bundles:

```bash
# Watch bundle status
kubectl get bundles -n fleet-default -w

# Expected bundles:
# - homelab-platform (CNI, Ingress)
# - homelab-storage (Longhorn)
# - homelab-core-services
# - homelab-edge-services
# - homelab-ops (Monitoring)
```

This may take 10-15 minutes for all components.

### Verify Deployment

```bash
# Check nodes are Ready (after CNI)
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check storage
kubectl get sc
kubectl get pods -n longhorn-system
```

## Step 9: Access Services

### Grafana Dashboard

```bash
make view-grafana
# Opens http://localhost:3000
# Username: admin
# Password: changeme
```

### Longhorn UI

```bash
make view-longhorn
# Opens http://localhost:8080
```

### Kubernetes Dashboard (Optional)

```bash
# Install dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin user
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin

# Get token
kubectl create token dashboard-admin -n kubernetes-dashboard

# Port-forward
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443

# Visit https://localhost:8443
```

## Step 10: Configure Edge Nodes

### Enable Wake-on-LAN

For each edge node:

1. Enter BIOS/UEFI (usually Del, F2, or F12 during boot)
2. Find power management settings
3. Enable:
   - Wake on LAN
   - Power On by PCI/PCIe Device
4. Disable:
   - ErP mode
   - Deep Sleep (S5)
5. Save and exit

### Test WoL

```bash
# Shutdown edge node
kubectl drain talos-edge-01 --ignore-daemonsets
talosctl -n 10.0.1.21 shutdown

# Wait for shutdown (30-60 seconds)

# Wake node
make wake-edge-01
# Or: ./scripts/wake-edge-nodes.sh talos-edge-01

# Check node comes back online
ping 10.0.1.21
kubectl get nodes -w
```

## Step 11: Deploy Workloads

### Core Service Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-core-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-core-app
  template:
    metadata:
      labels:
        app: my-core-app
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: core
      containers:
      - name: app
        image: nginx:alpine
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: my-core-app-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-core-app-data
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

### Edge Service Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-edge-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-edge-app
  template:
    metadata:
      labels:
        app: my-edge-app
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: edge
      tolerations:
      - key: node-role.kubernetes.io/edge
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: app
        image: my-batch-job:latest
```

## Troubleshooting

### Nodes Not Joining

```bash
# Check Talos logs
talosctl -n <NODE_IP> logs controller-runtime

# Check etcd members
talosctl -n 10.0.0.11 etcd members

# Check kubelet
talosctl -n <NODE_IP> logs kubelet
```

### Pods Not Starting

```bash
# Check CNI (Cilium)
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium

# Check pod events
kubectl describe pod <POD_NAME>

# Check node conditions
kubectl describe node <NODE_NAME>
```

### Storage Issues

```bash
# Check Longhorn
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# Check volumes
kubectl get pv
kubectl get pvc -A
```

See main [README.md](../README.md#troubleshooting) for more.

## Next Steps

1. **Set up backups**: Configure Longhorn backup targets
2. **Configure ingress**: Add DNS records for services
3. **Enable TLS**: Configure cert-manager with Let's Encrypt
4. **Add monitoring alerts**: Configure Alertmanager
5. **Harden security**: Review RBAC, network policies
6. **Document runbooks**: Procedures for common tasks

## Maintenance

### Regular Updates

```bash
# Update Talos
talosctl upgrade --nodes <NODE> --image ghcr.io/siderolabs/installer:v1.6.1

# Update Kubernetes
talosctl upgrade-k8s --nodes <NODE> --to 1.29.1

# Update Helm charts (via Fleet)
# Edit version in fleet/*/manifests.yaml and commit
```

### Backup etcd

```bash
# Snapshot etcd
talosctl -n 10.0.0.11 etcd snapshot etcd-backup-$(date +%Y%m%d).db

# Store securely off-cluster
```

### Monitoring

Check health regularly:
```bash
make check-health
```

## Support

- **Talos**: https://www.talos.dev/
- **Fleet**: https://fleet.rancher.io/
- **Longhorn**: https://longhorn.io/
- **Issues**: https://github.com/bjoernellens1/homelab-talos-opnsense/issues

## Cleanup

To start over:

```bash
# Remove all generated configs
make clean-all

# Wipe cluster nodes
talosctl -n <NODE> reset --graceful=false --reboot

# Or reinstall Talos from ISO
```
