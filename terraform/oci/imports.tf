# Import blocks for the existing hand-built estate. First run:
#   terraform plan -generate-config-out=generated.tf
# then hand-tidy generated.tf into network.tf / instances.tf (keep
# prevent_destroy on both instances) until plan is a no-op.
# Requires terraform >= 1.7 (variable references in import ids).

import {
  to = oci_core_vcn.homelab
  id = var.vcn_ocid
}

import {
  to = oci_core_subnet.homelab
  id = var.subnet_ocid
}

import {
  to = oci_core_internet_gateway.homelab
  id = var.internet_gateway_ocid
}

import {
  to = oci_core_route_table.homelab
  id = var.route_table_ocid
}

import {
  to = oci_core_instance.worker
  id = var.worker_instance_ocid
}

import {
  to = oci_core_instance.observability
  id = var.observability_instance_ocid
}
