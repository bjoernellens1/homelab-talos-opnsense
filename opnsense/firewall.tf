resource "opnsense_firewall_filter_rule" "allow_fritzbox_to_cluster" {
  sequence    = "1"
  action      = "pass"
  interface   = "wan"
  protocol    = "TCP/UDP"
  source_net  = opnsense_firewall_alias.fritzbox_net.name
  dest_net    = opnsense_firewall_alias.cluster_net.name
  dest_port   = "80,443,6443"
  description = "Allow Fritzbox Wi-Fi clients to access Cluster services"
}
