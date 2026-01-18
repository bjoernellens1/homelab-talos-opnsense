# Fleet GitOps Setup Guide

This guide walks through setting up Fleet GitOps for continuous deployment.

## Overview

Fleet monitors this Git repository and automatically deploys changes to the cluster. When you commit to the `fleet/` directory, Fleet synchronizes the changes to your cluster.

## Prerequisites

- Kubernetes cluster running (bootstrapped via `talos/bootstrap.sh`)
- `kubectl` configured with cluster access
- `helm` CLI installed

## Installation

### 1. Install Fleet

```bash
# Add Fleet Helm repository
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm repo update

# Install Fleet CRDs
helm install fleet-crd fleet/fleet-crd \
  -n cattle-fleet-system \
  --create-namespace \
  --wait

# Install Fleet
helm install fleet fleet/fleet \
  -n cattle-fleet-system \
  --wait
```

### 2. Verify Installation

```bash
# Check Fleet components are running
kubectl get pods -n cattle-fleet-system

# Should see:
# - fleet-controller
# - fleet-agent (one per cluster)
```

### 3. Register Git Repository

Create a GitRepo resource to monitor this repository:

```bash
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab
  namespace: fleet-default
spec:
  # Update with your repository URL
  repo: https://github.com/bjoernellens1/homelab-talos-opnsense
  
  # Branch to monitor
  branch: main
  
  # Paths to scan for bundles
  paths:
  - fleet
  
  # Poll interval (default: 15s)
  pollingInterval: 15s
  
  # Target clusters (local cluster by default)
  targets:
  - clusterSelector:
      matchLabels:
        cluster: homelab
EOF
```

### 4. Label Your Cluster

Fleet needs to know which cluster to deploy to:

```bash
# Get cluster name
CLUSTER_NAME=$(kubectl get clusters.fleet.cattle.io -n fleet-default -o jsonpath='{.items[0].metadata.name}')

# Add label
kubectl label clusters.fleet.cattle.io -n fleet-default "$CLUSTER_NAME" cluster=homelab
```

## Verify Deployment

### Check GitRepo Status

```bash
kubectl get gitrepo -n fleet-default homelab -o yaml
```

Look for:
- `status.conditions` - Should show `Ready: True`
- `status.commit` - Shows latest synced commit
- `status.summary` - Shows bundle deployment status

### Check Bundles

Fleet creates a Bundle for each directory in `fleet/`:

```bash
kubectl get bundles -n fleet-default

# Expected output:
# NAME                      READY   STATUS
# homelab-platform          True    
# homelab-storage           True    
# homelab-core-services     True    
# homelab-edge-services     True    
# homelab-ops              True    
```

### Check Bundle Content

```bash
# View bundle details
kubectl get bundle -n fleet-default homelab-platform -o yaml

# View resources deployed by bundle
kubectl get bundledeployment -n fleet-default
```

## Private Repository Setup

If using a private repository:

### 1. Create SSH Key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/fleet-homelab -N ""
```

### 2. Add Deploy Key to GitHub

1. Go to repository Settings → Deploy keys
2. Add public key (`~/.ssh/fleet-homelab.pub`)
3. Enable read access

### 3. Create Kubernetes Secret

```bash
kubectl create secret generic fleet-git-ssh \
  -n cattle-fleet-system \
  --from-file=ssh-privatekey=$HOME/.ssh/fleet-homelab \
  --from-literal=known_hosts="$(ssh-keyscan github.com)"
```

### 4. Update GitRepo to Use SSH

```bash
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: homelab
  namespace: fleet-default
spec:
  repo: git@github.com:bjoernellens1/homelab-talos-opnsense.git
  branch: main
  paths:
  - fleet
  
  # Reference SSH credentials
  clientSecretName: fleet-git-ssh
  
  targets:
  - clusterSelector:
      matchLabels:
        cluster: homelab
EOF
```

## Bundle Configuration

### Bundle Structure

Each directory under `fleet/` is a bundle:

```
fleet/
├── platform/
│   ├── fleet.yaml         # Bundle metadata
│   └── manifests.yaml     # Kubernetes resources
└── storage/
    ├── fleet.yaml
    └── manifests.yaml
```

### fleet.yaml Options

```yaml
name: my-bundle
namespace: fleet-default

# Target specific clusters
targetCustomizations:
- name: production
  clusterSelector:
    matchLabels:
      env: production
  
  # Override values for Helm charts
  helm:
    values:
      replicas: 3

# Dependencies (deploy this after another bundle)
dependsOn:
- name: platform

# Diff configuration (what to show in changes)
diff:
  comparePatches:
  - apiVersion: apps/v1
    kind: Deployment
    operations:
    - {"op": "remove", "path": "/spec/replicas"}
```

## Deployment Order

Fleet deploys bundles in parallel by default. To control order, use `dependsOn`:

```yaml
# storage/fleet.yaml
name: storage
dependsOn:
- name: platform  # Wait for platform bundle first
```

Recommended order:
1. **platform** (CNI, Ingress) - no dependencies
2. **storage** (Longhorn) - depends on platform
3. **core-services** - depends on storage
4. **edge-services** - depends on platform
5. **ops** (monitoring) - depends on storage

Add to each `fleet.yaml`:

```yaml
# storage/fleet.yaml
dependsOn:
- name: platform

# core-services/fleet.yaml
dependsOn:
- name: storage

# edge-services/fleet.yaml
dependsOn:
- name: platform

# ops/fleet.yaml
dependsOn:
- name: storage
```

## Working with Fleet

### Trigger Manual Sync

```bash
# Force immediate sync
kubectl annotate gitrepo homelab -n fleet-default \
  fleet.cattle.io/force-sync="$(date +%s)" --overwrite
```

### View Bundle Logs

```bash
# Fleet controller logs
kubectl logs -n cattle-fleet-system -l app=fleet-controller -f

# Fleet agent logs
kubectl logs -n cattle-fleet-system -l app=fleet-agent -f
```

### Pause/Resume GitRepo

```bash
# Pause (stop syncing)
kubectl patch gitrepo homelab -n fleet-default \
  --type=merge -p '{"spec":{"paused":true}}'

# Resume
kubectl patch gitrepo homelab -n fleet-default \
  --type=merge -p '{"spec":{"paused":false}}'
```

### Delete Bundle

```bash
# Remove bundle by deleting directory from Git
git rm -r fleet/my-bundle
git commit -m "Remove my-bundle"
git push

# Fleet will automatically remove resources
```

## Troubleshooting

### Bundle Stuck in "NotReady"

```bash
# Check bundle status
kubectl describe bundle -n fleet-default homelab-platform

# Common issues:
# 1. Helm chart download failure - check network
# 2. Resource conflicts - check existing resources
# 3. Invalid YAML - validate syntax
```

### Resources Not Applying

```bash
# Check bundle deployment
kubectl get bundledeployment -n fleet-default

# View errors
kubectl describe bundledeployment -n fleet-default <name>

# Check Fleet agent logs
kubectl logs -n cattle-fleet-system -l app=fleet-agent
```

### GitRepo Not Syncing

```bash
# Check GitRepo status
kubectl get gitrepo -n fleet-default homelab -o yaml

# Look for errors in status.conditions
# Common issues:
# 1. Authentication failure (SSH key)
# 2. Invalid repository URL
# 3. Branch doesn't exist
# 4. Network connectivity
```

### Force Bundle Redeploy

```bash
# Delete and recreate bundle deployment
kubectl delete bundledeployment -n fleet-default <bundle-name>

# Fleet will automatically recreate it
```

## Monitoring

### Prometheus Metrics

Fleet exposes metrics for monitoring:

```yaml
# ServiceMonitor for Fleet
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fleet
  namespace: cattle-fleet-system
spec:
  selector:
    matchLabels:
      app: fleet-controller
  endpoints:
  - port: metrics
```

Key metrics:
- `fleet_gitrepo_resources` - Resources in GitRepo
- `fleet_bundle_state` - Bundle deployment state
- `fleet_cluster_state` - Cluster state

### Grafana Dashboard

Import Fleet dashboard:
1. Grafana → Dashboards → Import
2. Dashboard ID: 15478
3. Select Prometheus data source

## Best Practices

1. **Test Changes**: Test bundle changes in a dev cluster first
2. **Small Commits**: Keep commits focused for easier rollback
3. **Version Pinning**: Pin Helm chart versions for reproducibility
4. **Resource Limits**: Set resource limits in all deployments
5. **Health Checks**: Define liveness and readiness probes
6. **Secrets**: Use SealedSecrets or external secret management
7. **Documentation**: Comment complex configurations

## Rolling Back

### Rollback via Git

```bash
# Find commit to rollback to
git log --oneline fleet/

# Revert commit
git revert <commit-sha>
git push

# Or reset to previous commit (destructive)
git reset --hard <commit-sha>
git push --force
```

### Manual Bundle Removal

```bash
# Temporarily remove bundle
kubectl delete bundle -n fleet-default homelab-platform

# Resources remain until bundle is redeployed
# Useful for emergency fixes
```

## Advanced: Multi-Cluster

Fleet can deploy to multiple clusters:

### 1. Register Additional Clusters

```bash
# From management cluster, generate registration token
kubectl create -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: ClusterRegistrationToken
metadata:
  name: prod-token
  namespace: fleet-default
spec:
  ttl: 720h
EOF

# Get registration command
kubectl get clusterregistrationtoken -n fleet-default prod-token -o jsonpath='{.status.token}'
```

### 2. Target Specific Clusters

```yaml
# fleet/platform/fleet.yaml
targetCustomizations:
- name: production
  clusterSelector:
    matchLabels:
      env: production
  helm:
    values:
      replicas: 5

- name: staging
  clusterSelector:
    matchLabels:
      env: staging
  helm:
    values:
      replicas: 2
```

## References

- [Fleet Documentation](https://fleet.rancher.io/)
- [Fleet GitHub](https://github.com/rancher/fleet)
- [GitOps with Fleet](https://fleet.rancher.io/gitops)
