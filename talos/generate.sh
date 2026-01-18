#!/usr/bin/env bash
set -euo pipefail

# Generate Talos configuration files for all nodes using patches
# This script reads inventory/nodes.yaml and generates configs with appropriate patches

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory/nodes.yaml"
PATCHES_DIR="$SCRIPT_DIR/patches"
OUTPUT_DIR="$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==> Generating Talos configurations...${NC}"

# Check for talosctl
if ! command -v talosctl &> /dev/null; then
    echo "Error: talosctl not found. Please install it first."
    echo "Visit: https://www.talos.dev/latest/introduction/getting-started/"
    exit 1
fi

# Parse cluster endpoint from inventory
CLUSTER_ENDPOINT=$(grep -A2 "^cluster:" "$INVENTORY" | grep "endpoint:" | awk '{print $2}')
CLUSTER_NAME=$(grep -A2 "^cluster:" "$INVENTORY" | grep "name:" | awk '{print $2}')

echo "Cluster Name: $CLUSTER_NAME"
echo "Cluster Endpoint: $CLUSTER_ENDPOINT"

# Generate secrets if they don't exist
if [ ! -f "$OUTPUT_DIR/secrets.yaml" ]; then
    echo -e "${YELLOW}Generating secrets...${NC}"
    talosctl gen secrets -o "$OUTPUT_DIR/secrets.yaml"
else
    echo "Secrets already exist, skipping generation"
fi

# Generate configs for core control plane nodes
echo -e "${GREEN}Generating core control plane configs...${NC}"
for i in 1 2 3; do
    NODE_IP="10.10.0.1$i"
    HOSTNAME="talos-core-0$i"
    
    talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" \
        --with-secrets "$OUTPUT_DIR/secrets.yaml" \
        --config-patch @"$PATCHES_DIR/core.yaml" \
        --output "$OUTPUT_DIR/controlplane-$HOSTNAME.yaml" \
        --output-types controlplane \
        --additional-sans "$NODE_IP" \
        --additional-sans "$HOSTNAME"
    
    echo "Generated: controlplane-$HOSTNAME.yaml"
done

# Generate configs for edge worker nodes
echo -e "${GREEN}Generating edge worker configs...${NC}"
for i in 1 2; do
    NODE_IP="10.10.0.2$i"
    HOSTNAME="talos-edge-0$i"
    
    talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" \
        --with-secrets "$OUTPUT_DIR/secrets.yaml" \
        --config-patch @"$PATCHES_DIR/edge.yaml" \
        --output "$OUTPUT_DIR/worker-$HOSTNAME.yaml" \
        --output-types worker
    
    echo "Generated: worker-$HOSTNAME.yaml"
done

# Generate talosconfig for cluster management
echo -e "${GREEN}Generating talosconfig...${NC}"
talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" \
    --with-secrets "$OUTPUT_DIR/secrets.yaml" \
    --output-types talosconfig \
    --output "$OUTPUT_DIR/talosconfig"

echo -e "${GREEN}==> Configuration generation complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Review generated configs in $OUTPUT_DIR"
echo "2. Apply configs to nodes: talosctl apply-config --insecure --nodes <NODE_IP> --file <CONFIG_FILE>"
echo "3. Bootstrap cluster: ./talos/bootstrap.sh"
