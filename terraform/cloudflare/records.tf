# Live records are imported, not recreated: run cf-terraforming per zone (see
# ../README.md) and tidy its output into this file until `terraform plan` is a
# no-op. Only the records below are asserted from the start because they are
# load-bearing for the redesign; everything else (MX, TXT/SPF, vanity zones)
# arrives via the import.
#
# Verified current shape (2026-09-08):
#   dbyte.xyz apex          A      -> relay (132.226.210.138)
#   *.dbyte.xyz             CNAME  -> dbyte.xyz          <- the wildcard Phase 4 removes
#   headscale.dbyte.xyz     A      -> worker (141.147.74.4)
#   james-hackett.ie apex   A      -> relay
#   photo.james-hackett.ie  CNAME  -> james-hackett.ie   (no wildcard on this zone)
#
# The post-split per-name public set lives in records-phase4.tf.example.

import {
  to = cloudflare_dns_record.headscale
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.headscale_record_id}"
}

variable "headscale_record_id" {
  type        = string
  description = "Record id of headscale.dbyte.xyz (cf-terraforming or the API lists these)"
}

# The control plane's name must resolve publicly everywhere — never through
# the tailnet it bootstraps, never at the relay.
resource "cloudflare_dns_record" "headscale" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "headscale.dbyte.xyz"
  type    = "A"
  content = var.worker_ipv4
  ttl     = 300
  proxied = false
}
