terraform {
  required_version = ">= 1.7"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }

  # OCI Object Storage via its S3-compatible API. Values live in backend.conf
  # (git-ignored, see backend.conf.example) because backend blocks cannot read
  # variables.
  backend "s3" {
    key = "oci/terraform.tfstate"
    # bucket, endpoints, region, credentials: -backend-config=backend.conf
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

# Auth from ~/.oci/config (`oci setup config` writes it): tenancy, user,
# fingerprint, key path and region all come from the profile, keeping
# identifying OCIDs out of this public repo.
provider "oci" {
  config_file_profile = "DEFAULT"
}
