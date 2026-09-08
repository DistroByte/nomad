terraform {
  required_version = ">= 1.7"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key                         = "cloudflare/terraform.tfstate"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

# Credentials via CLOUDFLARE_API_TOKEN from ../tf.sh — never in tfvars.
provider "cloudflare" {}

variable "relay_ipv4" {
  type        = string
  default     = "132.226.210.138"
  description = "observability.cloud — the public ingress today. At the UCG cutover decision gate this may become the home WAN IP."
}

variable "worker_ipv4" {
  type        = string
  default     = "141.147.74.4"
  description = "worker.cloud — headscale control plane; its records never point at the relay or home"
}

data "cloudflare_zones" "dbyte" {
  name = "dbyte.xyz"
}

data "cloudflare_zones" "james_hackett" {
  name = "james-hackett.ie"
}

data "cloudflare_zones" "ihatenixos" {
  name = "ihatenixos.org"
}

data "cloudflare_zones" "crazybitta" {
  name = "crazybitta.biz"
}

data "cloudflare_zones" "nicecocks" {
  name = "nicecocks.biz"
}
