terraform {
  required_version = ">= 1.7"

  required_providers {
    ns1 = {
      source  = "ns1-terraform/ns1"
      version = "~> 2.9"
    }
  }

  backend "s3" {
    key                         = "ns1/terraform.tfstate"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "ns1" {}

variable "ingress_ipv4" {
  type        = string
  default     = "185.152.73.180"
  description = "Public ingress: home (Blacknight static IPv4, forwarded by the ERX to Traefik on hermes). Failover to the relay is setting this to observability.cloud, 132.226.210.138, which serves every public router on websecure-proxied."
}
