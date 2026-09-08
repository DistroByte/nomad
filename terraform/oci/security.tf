# The one deliberate change in this root: the VCN's default security list
# currently allows everything from 0.0.0.0/0 and ::/0, leaving host iptables as
# the only real filter (and the v6 chains started empty — see docs/Headscale.md).
#
# oci_core_default_security_list adopts the existing default list on first
# apply (no import needed) and replaces its rules with the set below.
#
# Apply BEFORE adding the third Nomad/Consul server: without 41641/udp the
# cloud<->home tailscale path silently degrades to DERP.

locals {
  world_v4 = "0.0.0.0/0"
  world_v6 = "::/0"

  # port, protocol pairs opened to the world on both address families
  public_tcp_ports = [
    22,    # ssh (key-auth only; home is CGNAT so source-pinning is not viable)
    80,    # caddy (worker) / relay redirect (observability)
    443,   # caddy (worker) / relay https (observability)
    64738, # relay -> mumble
  ]
}

# Data source rather than the imported resource so this file stands alone —
# it must validate and apply before/without the generated instance config.
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

  # mumble voice is tcp+udp
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

  # tailscale direct path — required for cloud<->home cluster traffic to avoid
  # DERP relaying
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

  # gatus heartbeat from worker over the VCN private network only
  ingress_security_rules {
    protocol = "6"
    source   = var.vcn_cidr
    tcp_options {
      min = 8080
      max = 8080
    }
  }

  # path MTU discovery and reachability
  ingress_security_rules {
    protocol = "1" # icmp
    source   = local.world_v4
  }

  ingress_security_rules {
    protocol = "58" # icmpv6
    source   = local.world_v6
  }
}
