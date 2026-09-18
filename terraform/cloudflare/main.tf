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

provider "cloudflare" {}

variable "relay_ipv4" {
  type        = string
  default     = "132.226.210.138"
  description = "Public ingress. Back to observability.cloud on 2026-09-18: the Blacknight Genexis router serves its own admin UI on TCP 443 (Device.UserInterface.HTTPAccess.1.Port, writable in the model but not via the UI), so a 443 port-forward can never take effect — Blacknight confirmed external 443 is not possible on that unit and offered PPPoE details for a replacement. Home (185.152.73.180) does forward 80 and 64738 correctly and becomes primary again at the Phase 7 UCG cutover; until then the relay owns the apexes."
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
