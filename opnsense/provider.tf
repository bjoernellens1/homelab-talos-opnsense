terraform {
  required_providers {
    opnsense = {
      source  = "bpg/opnsense"
      version = "0.11.0"
    }
  }
}

provider "opnsense" {
  uri      = var.opnsense_url
  api_key  = var.opnsense_api_key
  api_secret = var.opnsense_api_secret
  allow_unverified_tls = true
}
