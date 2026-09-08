locals {
  world_v4 = "0.0.0.0/0"
  world_v6 = "::/0"

  public_tcp_ports = [
    22,
    80,
    443,
    64738,
  ]
}

data "oci_core_vcn" "homelab" {
  vcn_id = var.vcn_ocid
}

resource "oci_core_default_security_list" "homelab" {
  manage_default_resource_id = data.oci_core_vcn.homelab.default_security_list_id
  display_name               = "homelab"

  egress_security_rules {
    protocol    = "all"
    destination = local.world_v4
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.world_v6
  }

  dynamic "ingress_security_rules" {
    for_each = { for pair in setproduct(local.public_tcp_ports, [local.world_v4, local.world_v6]) :
    "${pair[0]}-${pair[1]}" => pair }
    content {
      protocol = "6" # tcp
      source   = ingress_security_rules.value[1]
      tcp_options {
        min = ingress_security_rules.value[0]
        max = ingress_security_rules.value[0]
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset([local.world_v4, local.world_v6])
    content {
      protocol = "17" # udp
      source   = ingress_security_rules.value
      udp_options {
        min = 64738
        max = 64738
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset([local.world_v4, local.world_v6])
    content {
      protocol = "17"
      source   = ingress_security_rules.value
      udp_options {
        min = 41641
        max = 41641
      }
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.vcn_cidr
    tcp_options {
      min = 8080
      max = 8080
    }
  }

  ingress_security_rules {
    protocol = "1" # icmp
    source   = local.world_v4
  }

  ingress_security_rules {
    protocol = "58" # icmpv6
    source   = local.world_v6
  }
}
