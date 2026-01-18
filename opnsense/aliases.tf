resource "opnsense_firewall_alias" "fritzbox_net" {
  name        = "fritzbox_net"
  type        = "network"
  description = "Fritzbox / WAN DMZ Network"
  content     = [var.fritzbox_network]
}

resource "opnsense_firewall_alias" "cluster_net" {
  name        = "cluster_net"
  type        = "network"
  description = "Talos Cluster Network"
  content     = [var.cluster_network]
}

resource "opnsense_firewall_alias" "node_core_01" {
  name        = "node_core_01"
  type        = "host"
  description = "talos-core-01"
  content     = ["10.10.0.11"]
}

resource "opnsense_firewall_alias" "node_core_02" {
  name        = "node_core_02"
  type        = "host"
  description = "talos-core-02"
  content     = ["10.10.0.12"]
}

resource "opnsense_firewall_alias" "node_core_03" {
  name        = "node_core_03"
  type        = "host"
  description = "talos-core-03"
  content     = ["10.10.0.13"]
}

resource "opnsense_firewall_alias" "node_edge_01" {
  name        = "node_edge_01"
  type        = "host"
  description = "talos-edge-01"
  content     = ["10.10.0.21"]
}

resource "opnsense_firewall_alias" "node_edge_02" {
  name        = "node_edge_02"
  type        = "host"
  description = "talos-edge-02"
  content     = ["10.10.0.22"]
}

resource "opnsense_firewall_alias" "k8s_api_vip" {
  name        = "k8s_api_vip"
  type        = "host"
  description = "Kubernetes API VIP"
  content     = ["10.10.0.10"]
}
