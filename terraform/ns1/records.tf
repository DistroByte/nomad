# The whole NS1 estate is one zone with one A record (verified against the API
# 2026-09-08), so it is asserted completely here rather than generated. The NS
# records are created and managed by NS1 itself — leave them out.
#
# ACME TXT challenges (_acme-challenge.pint.ing) are transient: Traefik's ns1
# resolver creates and removes them, so they never appear in config and any
# left behind by a crashed renewal are safe to delete.

import {
  to = ns1_zone.pint_ing
  id = "pint.ing"
}

# record import id format: zone/domain/type
import {
  to = ns1_record.pint_ing_apex
  id = "pint.ing/pint.ing/A"
}

resource "ns1_zone" "pint_ing" {
  zone    = "pint.ing"
  ttl     = 3600
  nx_ttl  = 3600
  refresh = 43200
}

resource "ns1_record" "pint_ing_apex" {
  zone   = ns1_zone.pint_ing.zone
  domain = "pint.ing"
  type   = "A"
  ttl    = 3600

  answers {
    answer = var.relay_ipv4
  }
}
