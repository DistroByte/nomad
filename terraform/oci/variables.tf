variable "compartment_ocid" {
  type        = string
  description = "Compartment holding the homelab VCN and instances"
}

variable "vcn_ocid" {
  type = string
}

variable "subnet_ocid" {
  type = string
}

variable "internet_gateway_ocid" {
  type = string
}

variable "route_table_ocid" {
  type = string
}

variable "worker_instance_ocid" {
  type        = string
  description = "worker.cloud (141.147.74.4) — headscale control plane"
}

variable "observability_instance_ocid" {
  type        = string
  description = "observability.cloud (132.226.210.138) — relay + gatus"
}

variable "vcn_cidr" {
  type        = string
  description = "The VCN's IPv4 CIDR (console → VCN details), e.g. 10.0.0.0/16"
}
