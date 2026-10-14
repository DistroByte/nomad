# dbyte.xyz names that resolve publicly. Everything else under dbyte.xyz is
# NXDOMAIN on the internet and resolves only via dionysus (LAN and tailnet);
# Traefik's internal-only allowlist is what actually keeps those private.
#
# Grey-cloud throughout: Mumble is raw L4 and Traefik terminates TLS, neither
# of which survives Cloudflare's proxy. TTL 300 keeps a failover flip fast.
locals {
  public_dbyte_names = [
    "immich",  # shared albums
    "request", # jellyseerr
    "share",   # mediashare (basicAuth)
    "mumble",  # voice, tcp+udp 64738
    "ha",      # home assistant, for the phone app away from home
    "vault",   # vaultwarden
    "molecule",
    "gerry",
    "video", # jellyfin
    "drive", # synology drive, on dionysus
  ]
}

import {
  for_each = toset(local.public_dbyte_names)
  to       = cloudflare_dns_record.public_dbyte[each.value]
  id       = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["public_${each.value}"]}"
}

resource "cloudflare_dns_record" "public_dbyte" {
  for_each = toset(local.public_dbyte_names)

  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "${each.value}.dbyte.xyz"
  type    = "A"
  content = var.ingress_ipv4
  ttl     = 300
  proxied = false
}
