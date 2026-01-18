#!/usr/bin/env python3
import yaml
import os
import subprocess
import sys

# Paths
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INVENTORY_PATH = os.path.join(REPO_ROOT, "inventory", "nodes.yaml")
OUTPUT_DIR = os.path.join(REPO_ROOT, "talos")
PATCHES_DIR = os.path.join(OUTPUT_DIR, "patches")

# Load Inventory
try:
    with open(INVENTORY_PATH, 'r') as f:
        inventory = yaml.safe_load(f)
except Exception as e:
    print(f"Error loading inventory: {e}")
    sys.exit(1)

cluster_name = inventory['cluster']['name']
cluster_endpoint = inventory['cluster']['endpoint']
print(f"Generating configs for cluster: {cluster_name} at {cluster_endpoint}")

# Generate Secrets
secrets_path = os.path.join(OUTPUT_DIR, "secrets.yaml")
if not os.path.exists(secrets_path):
    print("Generating secrets...")
    subprocess.run(["talosctl", "gen", "secrets", "-o", secrets_path], check=True)
else:
    print("Secrets already exist, skipping.")

def generate_config(node, output_type):
    hostname = node['hostname']
    ip = node['ip']
    role = node['role']
    # Determine patch file
    patch_file = "core.yaml" if "core" in hostname else "edge.yaml"
    patch_path = os.path.join(PATCHES_DIR, patch_file)

    # Generate node-specific network patch
    # Use one network for everything. Realtek 2.5G is the priority.
    node_patch = {
        "machine": {
            "install": {
                "disk": node['specs']['disk']
            },
            "network": {
                "hostname": hostname,
                "interfaces": [
                    {
                        "addresses": [f"{ip}/24"],
                        "routes": [
                            {
                                "network": "0.0.0.0/0",
                                "gateway": inventory['network']['gateway']
                            }
                        ],
                        "deviceSelector": {
                            "driver": "r8152" if "core" in hostname else "*"
                        }
                    }
                ],
                "nameservers": inventory['network']['nameservers']
            }
        }
    }
    
    # Add VIP for control plane on the main interface
    if role == "controlplane" and hostname == "talos-core-01":
         node_patch["machine"]["network"]["interfaces"][0]["vip"] = {
             "ip": "10.10.0.10"
         }
    
    node_patch_path = os.path.join(OUTPUT_DIR, f"patch-{hostname}.yaml")
    with open(node_patch_path, 'w') as f:
        yaml.dump(node_patch, f)

    output_prefix = "controlplane" if role == "controlplane" else "worker"
    output_file = os.path.join(OUTPUT_DIR, f"{output_prefix}-{hostname}.yaml")
    
    cmd = [
        "talosctl", "gen", "config", cluster_name, cluster_endpoint,
        "--with-secrets", secrets_path,
        "--config-patch", f"@{patch_path}",
        "--config-patch", f"@{node_patch_path}",
        "--output", output_file,
        "--output-types", role if role == "controlplane" else "worker",
        "-f"
    ]
    
    if role == "controlplane":
        cmd.extend(["--additional-sans", ip, "--additional-sans", hostname, "--additional-sans", "10.10.0.10"])
        
    print(f"Generating {output_file}...")
    subprocess.run(cmd, check=True)
    
    # Clean up node patch
    os.remove(node_patch_path)

# Process Core Nodes
for node in inventory.get('core_nodes', []):
    generate_config(node, node['role'])

# Process Edge Nodes
for node in inventory.get('edge_nodes', []):
    generate_config(node, "worker")

# Generate talosconfig
print("Generating talosconfig...")
subprocess.run([
    "talosctl", "gen", "config", cluster_name, cluster_endpoint,
    "--with-secrets", secrets_path,
    "--output-types", "talosconfig",
    "--output", os.path.join(OUTPUT_DIR, "talosconfig"),
    "-f"
], check=True)

print("\nDone! All nodes configured with single 2.5G/Main network.")
