# Energy Tuning and Power Management

This document describes the energy optimization strategies for the homelab, focusing on edge node power management and overall cluster efficiency.

## Overview

The homelab uses a tiered approach to energy management:
- **Core nodes**: Always-on, optimized for performance and reliability
- **Edge nodes**: On-demand via Wake-on-LAN, optimized for energy savings

## Architecture

```
┌──────────────────────────────────────┐
│          Core Nodes (24/7)           │
│  - Control Plane (3 nodes)           │
│  - Storage Workers (2 nodes)         │
│  - Always-on, performance-optimized  │
└──────────────────────────────────────┘
                   │
                   │ WoL Control
                   ▼
┌──────────────────────────────────────┐
│      Edge Nodes (On-Demand)          │
│  - Wake on schedule or trigger       │
│  - Power off when idle               │
│  - Energy-optimized workloads        │
└──────────────────────────────────────┘
```

## Energy Consumption Estimates

### Core Nodes (Always-On)
- Control plane nodes: ~30W each × 3 = 90W
- Storage workers: ~50W each × 2 = 100W
- Network equipment: ~30W
- **Total baseline**: ~220W (5.3 kWh/day, ~160 kWh/month)

### Edge Nodes (On-Demand)
- Active: ~40W each × 3 = 120W
- Idle/Sleep: ~2W each × 3 = 6W
- Average usage: 4 hours/day active
- **Savings**: ~90W × 20 hours/day = 1.8 kWh/day (~54 kWh/month)

### Total Savings
Operating edge nodes on-demand vs 24/7: **~40% reduction in edge node energy costs**

## Wake-on-LAN (WoL) Configuration

### BIOS/UEFI Settings

For each edge node, enable in BIOS:

1. **Wake on LAN**: Enabled
2. **Deep Sleep States**: Disabled (for reliable wake)
3. **ErP**: Disabled (blocks WoL)
4. **Power On by PCI/PCIe Device**: Enabled
5. **Restore on AC Power Loss**: Last State (or Power Off)

### Network Interface Configuration

For Talos Linux edge nodes, WoL is configured via the patch in `talos/patches/edge.yaml`. The network interface must support WoL.

Verify WoL support on the interface:
```bash
ethtool eth0 | grep Wake-on
```

Should show: `Wake-on: g` (magic packet wake)

### OPNsense WoL Configuration

OPNsense can send WoL packets:

1. Navigate to **Services → Wake on LAN**
2. Add entries for each edge node:
   - Interface: LAN
   - MAC Address: (from inventory/nodes.yaml)
   - Description: Node hostname

Or use the WoL API:
```bash
curl -X POST http://10.0.0.1/api/wol/wake/talos-edge-01
```

## Automated Wake/Sleep Schedules

### Wake Edge Nodes on Schedule

Deploy the CronJob from `scripts/wol-gateway.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: wake-edge-nodes
spec:
  schedule: "0 6 * * 1-5"  # 6 AM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: wake
            image: curlimages/curl:latest
            command: ["/bin/sh", "-c"]
            args:
            - |
              curl -X POST http://wol-gateway:8080/wake/all
```

### Shutdown Edge Nodes When Idle

Deploy auto-shutdown daemonset on edge nodes:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: auto-shutdown
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: auto-shutdown
  template:
    metadata:
      labels:
        app: auto-shutdown
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: edge
      tolerations:
      - key: node-role.kubernetes.io/edge
        operator: Exists
      hostPID: true
      hostNetwork: true
      containers:
      - name: auto-shutdown
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            # Check if any pods are running (excluding system pods)
            PODS=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$NODE_NAME \
              -o json | jq '[.items[] | select(.metadata.namespace != "kube-system")] | length')
            
            if [ "$PODS" -eq 0 ]; then
              # Check idle time
              IDLE=$(cat /proc/uptime | awk '{print int($1/60)}')
              if [ "$IDLE" -gt 30 ]; then
                echo "No workloads for 30 minutes, shutting down..."
                shutdown -h now
              fi
            fi
            sleep 300  # Check every 5 minutes
          done
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

## CPU Power Management

### Talos Linux CPU Frequency Scaling

Edge nodes use CPU frequency scaling for power savings. This is configured via kernel parameters in the Talos patch:

```yaml
machine:
  kernel:
    modules:
      - name: acpi_cpufreq
      - name: cpufreq_powersave
```

### CPU Governor

Edge nodes use `powersave` governor for energy efficiency:

```bash
# Check current governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Set to powersave (Talos does this automatically with edge patch)
echo powersave > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Core nodes use `performance` governor for consistent latency.

## Storage Power Management

### Longhorn on Core Nodes Only

By restricting Longhorn to core nodes (`storage-node: "true"` label), we:
- Keep storage always available
- Avoid data migration between nodes
- Eliminate storage overhead on edge nodes
- Reduce edge node power consumption

### Disk Spin-Down (Not Recommended)

For edge nodes with HDDs, spin-down can save power but:
- Increases latency on wake
- Reduces disk lifespan (spin-up cycles)
- Not beneficial for SSDs

**Decision**: Keep disks active when nodes are on.

## Network Power Management

### Energy-Efficient Ethernet (EEE)

Enable EEE on network switches and NICs:

```bash
# Check EEE status
ethtool --show-eee eth0

# Enable EEE
ethtool --set-eee eth0 eee on
```

Benefits:
- Reduces power during low traffic
- ~20-30% network power savings
- No noticeable performance impact

### Link Speed Negotiation

Edge nodes can use 1Gbps links instead of 10Gbps:
- 1Gbps: ~2-3W per port
- 10Gbps: ~5-8W per port
- Sufficient for edge workloads

## Monitoring Energy Usage

### Prometheus Metrics

Deploy power monitoring:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: power-monitoring
  namespace: monitoring
data:
  prometheus-rules.yaml: |
    groups:
    - name: power
      interval: 60s
      rules:
      - record: node_power_watts
        expr: node_hwmon_power_watt
      
      - alert: EdgeNodeHighPower
        expr: node_power_watts{zone="edge"} > 60
        for: 10m
        annotations:
          summary: "Edge node using excessive power"
```

### Node Uptime Tracking

Track edge node uptime to measure power savings:

```bash
# Query Prometheus
sum(node_boot_time_seconds{zone="edge"})
```

Calculate energy savings:
```
Savings = (Total_Hours - Uptime_Hours) × Power_Per_Node × Cost_Per_kWh
```

## Best Practices

### Workload Scheduling

1. **Core Services**: Always on core nodes
   - Databases
   - Message queues
   - Persistent storage

2. **Batch Jobs**: Schedule on edge nodes
   - Nightly processing
   - Data analysis
   - CI/CD pipelines

3. **Bursty Workloads**: Use edge nodes
   - Development environments
   - Test clusters
   - Infrequent services

### Kubernetes Node Affinity

Example workload for edge nodes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  template:
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: edge
      tolerations:
      - key: node-role.kubernetes.io/edge
        operator: Equal
        value: "true"
        effect: NoSchedule
      # Wake nodes before scheduling
      initContainers:
      - name: wake-node
        image: curlimages/curl
        command:
        - curl
        - -X
        - POST
        - http://wol-gateway.wol-gateway:8080/wake/all
```

## OPNsense Power Features

### Traffic Shaping for Off-Peak

Configure traffic shaping in OPNsense to reduce bandwidth during off-peak:

1. Navigate to **Firewall → Traffic Shaper**
2. Create schedule: High bandwidth (6 AM - 10 PM), Low bandwidth (10 PM - 6 AM)
3. Reduces switch/router power consumption

### DNS Caching

Unbound DNS caching reduces upstream queries:
- Fewer packets = less NIC power
- Faster responses = less CPU time
- Configure in `docs/opnsense-split-dns.md`

## Measuring Success

### Monthly Energy Reports

Track metrics:
1. **Total kWh consumed**: From power meter or UPS
2. **Edge node uptime %**: From Kubernetes metrics
3. **Cost savings**: Compare to 24/7 operation
4. **Performance impact**: Check SLAs met

### Example Report

```
Month: January 2024
- Total energy: 195 kWh (baseline: 280 kWh)
- Savings: 85 kWh (30%)
- Cost savings: $12.75 (@$0.15/kWh)
- Edge uptime: 35% (target: 30-40%)
- SLA met: 100%
- CO2 avoided: ~45 kg
```

## Future Optimizations

1. **Solar integration**: Power core nodes from solar during day
2. **Battery backup**: Use UPS to shift load to off-peak hours
3. **Dynamic scaling**: Auto-scale core workers based on load
4. **ARM nodes**: Lower power consumption per core
5. **Liquid cooling**: Improved efficiency for high-density core nodes

## Troubleshooting

### Edge Nodes Won't Wake

1. Check WoL enabled in BIOS
2. Verify MAC address in inventory
3. Test WoL manually: `wakeonlan -i 10.0.0.255 <MAC>`
4. Check OPNsense firewall allows UDP port 9
5. Ensure node is in S3/S4 sleep, not S5 (off)

### Nodes Sleep Too Aggressively

1. Adjust idle timeout in auto-shutdown script
2. Check for workload leaks (pods not terminating)
3. Increase minimum uptime threshold

### High Power Draw When Idle

1. Check CPU governor: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
2. Verify EEE enabled: `ethtool --show-eee eth0`
3. Disable unused peripherals in BIOS
4. Check for runaway processes

## References

- [Talos Linux Power Management](https://www.talos.dev/latest/)
- [Kubernetes Node Power Management](https://kubernetes.io/docs/concepts/architecture/nodes/)
- [Wake-on-LAN Protocol](https://en.wikipedia.org/wiki/Wake-on-LAN)
- [Energy Efficient Ethernet](https://en.wikipedia.org/wiki/Energy-Efficient_Ethernet)
