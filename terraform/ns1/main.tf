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

# Credentials via NS1_APIKEY from ../tf.sh — never in tfvars.
provider "ns1" {}

variable "relay_ipv4" {
  type        = string
  default     = "132.226.210.138"
  description = "observability.cloud — the public ingress today. At the UCG cutover decision gate this may become the home WAN IP."
}
