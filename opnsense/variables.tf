variable "opnsense_url" {
  type        = string
  description = "The URL of the OPNsense API (e.g., https://10.1.10.2)"
}

variable "opnsense_api_key" {
  type        = string
  description = "The OPNsense API Key"
  sensitive   = true
}

variable "opnsense_api_secret" {
  type        = string
  description = "The OPNsense API Secret"
  sensitive   = true
}

variable "fritzbox_network" {
  type        = string
  default     = "10.1.10.0/24"
  description = "The network CIDR of the Fritzbox / DMZ layer"
}

variable "cluster_network" {
  type        = string
  default     = "10.10.0.0/24"
  description = "The network CIDR of the Cluster layer"
}

variable "domain_internal" {
  type        = string
  default     = "home.arpa"
  description = "The internal domain for homelab services"
}

variable "domain_cluster" {
  type        = string
  default     = "cluster.local"
  description = "The internal domain for the Kubernetes cluster"
}
