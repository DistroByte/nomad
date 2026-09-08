resource "oci_core_vcn" "homelab" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "vcn-20210615-0014"
  dns_label      = "vcn06150019"
  is_ipv6enabled = true
  freeform_tags  = {}
}

resource "oci_core_subnet" "homelab" {
  vcn_id                     = oci_core_vcn.homelab.id
  compartment_id             = var.compartment_ocid
  cidr_block                 = "10.0.0.0/24"
  display_name               = "gerry"
  dns_label                  = "subnet06150019"
  route_table_id             = oci_core_route_table.homelab.id
  security_list_ids          = [data.oci_core_vcn.homelab.default_security_list_id]
  dhcp_options_id            = "ocid1.dhcpoptions.oc1.uk-london-1.aaaaaaaaddjwt6dyp56krhiyh3s4ehmf5urp7geqqgiiq7uizksqbviombkq"
  ipv6cidr_block             = "2603:c020:c014:4eff::/64"
  prohibit_internet_ingress  = false
  prohibit_public_ip_on_vnic = false
  freeform_tags              = {}
}

resource "oci_core_internet_gateway" "homelab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "Internet Gateway vcn-20210615-0014"
  enabled        = true
  freeform_tags  = {}
}

resource "oci_core_route_table" "homelab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "Default Route Table for vcn-20210615-0014"
  freeform_tags  = {}

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.homelab.id
    route_type        = "STATIC"
  }
  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.homelab.id
    route_type        = "STATIC"
  }
}
