#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Talos Kubernetes cluster
# This script initializes the control plane and configures kubectl access

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory/nodes.yaml"
TALOSCONFIG="$SCRIPT_DIR/talosconfig"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}==> Bootstrapping Talos Kubernetes cluster...${NC}"

# Check for required tools
for cmd in talosctl kubectl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd not found. Please install it first.${NC}"
        exit 1
    fi
done

# Check if talosconfig exists
if [ ! -f "$TALOSCONFIG" ]; then
    echo -e "${RED}Error: talosconfig not found at $TALOSCONFIG${NC}"
    echo "Please run ./talos/generate.py first"
    exit 1
fi

# Set talosconfig
export TALOSCONFIG="$TALOSCONFIG"

# Parse first control plane node from inventory
BOOTSTRAP_NODE="10.10.0.11"  # talos-core-01

echo "Using bootstrap node: $BOOTSTRAP_NODE"

# Wait for nodes to be ready
echo -e "${YELLOW}Waiting for control plane nodes to be ready...${NC}"
echo "This may take a few minutes..."

# Check if nodes are reachable
for i in {1..30}; do
    if talosctl -n "$BOOTSTRAP_NODE" version &> /dev/null; then
        echo -e "${GREEN}Node $BOOTSTRAP_NODE is reachable${NC}"
        break
    fi
    echo "Attempt $i/30: Node not ready yet..."
    sleep 10
done

# Bootstrap etcd on first control plane node
echo -e "${GREEN}Bootstrapping etcd on $BOOTSTRAP_NODE...${NC}"
talosctl -n "$BOOTSTRAP_NODE" bootstrap

echo -e "${YELLOW}Waiting for cluster to initialize...${NC}"
sleep 30

# Wait for Kubernetes API to be ready
echo -e "${YELLOW}Waiting for Kubernetes API...${NC}"
for i in {1..60}; do
    if talosctl -n "$BOOTSTRAP_NODE" kubeconfig &> /dev/null; then
        break
    fi
    echo "Attempt $i/60: API not ready yet..."
    sleep 10
done

# Retrieve kubeconfig
echo -e "${GREEN}Retrieving kubeconfig...${NC}"
talosctl -n "$BOOTSTRAP_NODE" kubeconfig "$SCRIPT_DIR/kubeconfig"

# Export kubeconfig
export KUBECONFIG="$SCRIPT_DIR/kubeconfig"

echo -e "${YELLOW}Waiting for all control plane nodes to join...${NC}"
sleep 30

# Check cluster status
echo -e "${GREEN}Cluster Status:${NC}"
kubectl get nodes -o wide

echo ""
echo -e "${GREEN}==> Bootstrap complete!${NC}"
echo ""
echo "Cluster configuration:"
echo "  TALOSCONFIG: $TALOSCONFIG"
echo "  KUBECONFIG: $SCRIPT_DIR/kubeconfig"
echo ""
echo "To use this cluster:"
echo "  export TALOSCONFIG=$TALOSCONFIG"
echo "  export KUBECONFIG=$SCRIPT_DIR/kubeconfig"
echo ""
echo "Next steps:"
echo "1. Wait for all nodes to join: kubectl get nodes -w"
echo "2. Install CNI (via Fleet platform bundle)"
echo "3. Deploy Fleet GitOps"
echo "4. Apply remaining Fleet bundles"
