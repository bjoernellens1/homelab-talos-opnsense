resource "opnsense_unbound_host_override" "api_cluster_local" {
  enabled     = true
  hostname    = "api"
  domain      = var.domain_cluster
  server      = "10.10.0.10"
  description = "Kubernetes API VIP"
}

resource "opnsense_unbound_host_override" "talos_core_01" {
  enabled     = true
  hostname    = "talos-core-01"
  domain      = var.domain_internal
  server      = "10.10.0.11"
  description = "Control plane node 1"
}

resource "opnsense_unbound_host_override" "talos_core_02" {
  enabled     = true
  hostname    = "talos-core-02"
  domain      = var.domain_internal
  server      = "10.10.0.12"
  description = "Control plane node 2"
}

resource "opnsense_unbound_host_override" "talos_core_03" {
  enabled     = true
  hostname    = "talos-core-03"
  domain      = var.domain_internal
  server      = "10.10.0.13"
  description = "Control plane node 3"
}

resource "opnsense_unbound_host_override" "talos_edge_01" {
  enabled     = true
  hostname    = "talos-edge-01"
  domain      = var.domain_internal
  server      = "10.10.0.21"
  description = "Edge worker node 1"
}

resource "opnsense_unbound_host_override" "talos_edge_02" {
  enabled     = true
  hostname    = "talos-edge-02"
  domain      = var.domain_internal
  server      = "10.10.0.22"
  description = "Edge worker node 2"
}

resource "opnsense_unbound_host_override" "jellyfin" {
  enabled     = true
  hostname    = "jellyfin"
  domain      = var.domain_internal
  server      = "10.10.0.50"
  description = "Jellyfin service"
}

resource "opnsense_unbound_host_override" "opencloud" {
  enabled     = true
  hostname    = "opencloud"
  domain      = var.domain_internal
  server      = "10.10.0.50"
  description = "OpenCloud service"
}

resource "opnsense_unbound_host_override" "wol" {
  enabled     = true
  hostname    = "wol"
  domain      = var.domain_internal
  server      = "10.10.0.60"
  description = "Wake-on-LAN gateway"
}

# Domain Overrides
resource "opnsense_unbound_domain_override" "cluster_local" {
  enabled = true
  domain  = var.domain_cluster
  server  = "10.10.0.10"
}

resource "opnsense_unbound_domain_override" "home_arpa" {
  enabled = true
  domain  = var.domain_internal
  server  = "10.10.0.1"
}
