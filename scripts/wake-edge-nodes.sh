#!/usr/bin/env bash
set -euo pipefail

# Wake-on-LAN script for edge nodes
# Sends magic packets to wake edge nodes on demand

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory/nodes.yaml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check for wakeonlan tool
if ! command -v wakeonlan &> /dev/null; then
    echo -e "${RED}Error: wakeonlan not found${NC}"
    echo "Install it with: sudo apt-get install wakeonlan"
    echo "Or: brew install wakeonlan"
    exit 1
fi

# Function to wake a node
wake_node() {
    local hostname=$1
    local mac=$2
    local ip=$3
    
    echo -e "${YELLOW}Waking $hostname ($mac)...${NC}"
    wakeonlan -i 10.10.0.255 "$mac"
    
    echo -e "${YELLOW}Waiting for $hostname to come online...${NC}"
    for i in {1..30}; do
        if ping -c 1 -W 1 "$ip" &> /dev/null; then
            echo -e "${GREEN}$hostname is online!${NC}"
            return 0
        fi
        sleep 2
    done
    
    echo -e "${RED}Warning: $hostname did not respond within 60 seconds${NC}"
    return 1
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <edge-node-name|all>"
    echo ""
    echo "Available edge nodes:"
    echo "  talos-edge-01 (10.10.0.21)"
    echo "  talos-edge-02 (10.10.0.22)"
    echo "  all           (wake all edge nodes)"
    exit 1
fi

case "$1" in
    talos-edge-01)
        wake_node "talos-edge-01" "00:00:00:00:01:01" "10.10.0.21"
        ;;
    talos-edge-02)
        wake_node "talos-edge-02" "00:00:00:00:01:02" "10.10.0.22"
        ;;
    all)
        echo -e "${GREEN}Waking all edge nodes...${NC}"
        wake_node "talos-edge-01" "00:00:00:00:01:01" "10.10.0.21"
        wake_node "talos-edge-02" "00:00:00:00:01:02" "10.10.0.22"
        ;;
    *)
        echo -e "${RED}Error: Unknown node '$1'${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Done!${NC}"
