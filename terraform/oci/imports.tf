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
