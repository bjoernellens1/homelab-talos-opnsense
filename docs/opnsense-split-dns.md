# OPNsense Split DNS Configuration

This document describes the split DNS setup for the homelab Talos/OPNsense environment.

## Overview

Split DNS allows the cluster to resolve internal hostnames while still accessing external DNS for internet domains. OPNsense acts as the primary DNS server for all cluster nodes.

## Architecture

```
┌─────────────────┐
│   Talos Nodes   │
│  (10.0.0.0/16)  │
└────────┬────────┘
         │
         │ DNS Queries
         ▼
┌─────────────────┐
│    OPNsense     │
│   10.0.0.1      │
├─────────────────┤
│  Unbound DNS    │
└────────┬────────┘
         │
         ├─ Internal: cluster.local, *.homelab → Local resolution
         └─ External: *.com, *.org, etc. → Upstream (1.1.1.1, 8.8.8.8)
```

## Configuration Steps

### 1. Enable Unbound DNS

1. Navigate to **Services → Unbound DNS → General**
2. Enable Unbound DNS Resolver
3. Set **Listen Port**: 53
4. Set **Network Interfaces**: LAN (where cluster nodes are)

### 2. Configure Custom Domain Overrides

Navigate to **Services → Unbound DNS → Overrides**

#### Host Overrides

Add the following host overrides for cluster infrastructure:

| Host | Domain | IP Address | Description |
|------|--------|------------|-------------|
| api | cluster.local | 10.0.0.10 | Kubernetes API VIP |
| talos-core-01 | cluster.local | 10.0.0.11 | Control plane node 1 |
| talos-core-02 | cluster.local | 10.0.0.12 | Control plane node 2 |
| talos-core-03 | cluster.local | 10.0.0.13 | Control plane node 3 |
| talos-core-04 | cluster.local | 10.0.0.14 | Core worker node 1 |
| talos-core-05 | cluster.local | 10.0.0.15 | Core worker node 2 |
| talos-edge-01 | cluster.local | 10.0.1.21 | Edge worker node 1 |
| talos-edge-02 | cluster.local | 10.0.1.22 | Edge worker node 2 |
| talos-edge-03 | cluster.local | 10.0.1.23 | Edge worker node 3 |
| ingress | homelab | 10.0.0.100 | Ingress controller |
| longhorn | homelab | 10.0.0.101 | Longhorn UI |
| grafana | homelab | 10.0.0.102 | Grafana dashboard |

#### Domain Overrides

Add domain overrides to resolve entire domains locally:

| Domain | IP Address | Description |
|--------|------------|-------------|
| cluster.local | 10.0.0.10 | Cluster internal domain |
| homelab | 10.0.0.1 | Homelab services |

### 3. Configure Upstream DNS Servers

Navigate to **System → Settings → General**

Add upstream DNS servers:
- Primary: 1.1.1.1 (Cloudflare)
- Secondary: 8.8.8.8 (Google)
- Tertiary: 1.0.0.1 (Cloudflare)

Enable **DNS Server Override**: Unchecked (to use configured servers)

### 4. Enable DNS Query Forwarding

Navigate to **Services → Unbound DNS → General**

- **Enable Forwarding Mode**: Checked
- This forwards queries to upstream DNS for non-local domains

### 5. Configure DNSSEC

Navigate to **Services → Unbound DNS → General**

- **Enable DNSSEC Support**: Checked
- Validates DNS responses to prevent spoofing

### 6. Local Zone Configuration

Navigate to **Services → Unbound DNS → Advanced**

Add custom configuration:

```
server:
  # Local zones for cluster
  local-zone: "cluster.local." static
  local-zone: "homelab." static
  
  # Respond authoritatively for local domains
  local-zone: "0.0.10.in-addr.arpa." static
  local-zone: "1.0.10.in-addr.arpa." static
  
  # Private address ranges
  private-address: 10.0.0.0/16
  
  # Cache tuning
  cache-min-ttl: 60
  cache-max-ttl: 86400
  
  # Performance tuning
  num-threads: 4
  msg-cache-slabs: 4
  rrset-cache-slabs: 4
  infra-cache-slabs: 4
  key-cache-slabs: 4
```

## Testing

### From a Cluster Node

```bash
# Test internal resolution
nslookup talos-core-01.cluster.local
nslookup api.cluster.local

# Test external resolution
nslookup google.com
nslookup github.com

# Test reverse lookup
nslookup 10.0.0.11
```

### From OPNsense

Navigate to **Services → Unbound DNS → Query Log** to view DNS queries.

## PTR Records (Reverse DNS)

For proper reverse DNS:

1. Navigate to **Services → Unbound DNS → Overrides**
2. For each host override, ensure **PTR Record** is checked

## DNS Caching

Unbound automatically caches DNS responses. To clear cache:

1. Navigate to **Services → Unbound DNS → General**
2. Click **Restart Service**

Or via CLI:
```bash
unbound-control flush_zone cluster.local
unbound-control reload
```

## Monitoring

Monitor DNS queries and performance:

1. Navigate to **Services → Unbound DNS → Query Log**
2. Enable query logging temporarily for debugging
3. View statistics: **Services → Unbound DNS → Statistics**

## Troubleshooting

### Nodes Can't Resolve Internal Names

1. Verify OPNsense firewall rules allow DNS (port 53)
2. Check Unbound is listening on correct interface
3. Verify host overrides are configured correctly
4. Check `/etc/resolv.conf` on nodes points to 10.0.0.1

### Slow DNS Resolution

1. Increase cache sizes in Advanced settings
2. Add more upstream DNS servers
3. Enable prefetch: `prefetch: yes` in custom config

### DNS Leaks

Ensure all nodes use OPNsense as their only DNS server. Verify in Talos configs:

```yaml
machine:
  network:
    nameservers:
      - 10.0.0.1
```

## Security Considerations

1. **Access Control Lists**: Restrict DNS queries to internal networks only
2. **DNSSEC**: Always enable to prevent DNS spoofing
3. **Rate Limiting**: Enable to prevent DNS amplification attacks
4. **Query Logging**: Disable in production for privacy and performance

## References

- [OPNsense Unbound DNS Documentation](https://docs.opnsense.org/manual/unbound.html)
- [Talos Network Configuration](https://www.talos.dev/latest/reference/configuration/#machine-network)
- [Split DNS Best Practices](https://en.wikipedia.org/wiki/Split-horizon_DNS)
