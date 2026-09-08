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
#
# NOTE: *.ihatenixos.org and *.crazybitta.biz are the same wildcard-to-relay
# pattern as *.dbyte.xyz — Phase 4 should account for all three zones, not
# just dbyte.xyz.

variable "record_ids" {
  type        = map(string)
  description = "Cloudflare DNS record ids for import, keyed by a descriptive name (API lists these per zone)"
}

# ---------------------------------------------------------------------------
# dbyte.xyz
# ---------------------------------------------------------------------------

import {
  to = cloudflare_dns_record.dbyte_apex
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["dbyte_apex"]}"
}
resource "cloudflare_dns_record" "dbyte_apex" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "dbyte.xyz"
  type    = "A"
  content = var.relay_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.headplane
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["headplane"]}"
}
# Same "must resolve publicly, never via relay" logic as headscale below.
resource "cloudflare_dns_record" "headplane" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "headplane.dbyte.xyz"
  type    = "A"
  content = var.worker_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.headscale
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["headscale_a"]}"
}
# The control plane's name must resolve publicly everywhere — never through
# the tailnet it bootstraps, never at the relay.
resource "cloudflare_dns_record" "headscale" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "headscale.dbyte.xyz"
  type    = "A"
  content = var.worker_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.headscale_aaaa
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["headscale_aaaa"]}"
}
resource "cloudflare_dns_record" "headscale_aaaa" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "headscale.dbyte.xyz"
  type    = "AAAA"
  content = "2603:c020:c014:4eff::10"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.dbyte_wildcard
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["dbyte_wildcard"]}"
}
# The wildcard Phase 4 replaces with the per-name public record set in
# records-phase4.tf.example — do not remove until that ships.
resource "cloudflare_dns_record" "dbyte_wildcard" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "*.dbyte.xyz"
  type    = "CNAME"
  content = "dbyte.xyz"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.i_dbyte_cname
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["i_dbyte_cname"]}"
}
# Third-party (Google Cloud Storage), unrelated to the relay.
resource "cloudflare_dns_record" "i_dbyte_cname" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "i.dbyte.xyz"
  type    = "CNAME"
  content = "c.storage.googleapis.com"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.dbyte_spf
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["dbyte_spf"]}"
}
resource "cloudflare_dns_record" "dbyte_spf" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "dbyte.xyz"
  type    = "TXT"
  content = "\"v=spf1 -all\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.dbyte_dmarc
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["dbyte_dmarc"]}"
}
resource "cloudflare_dns_record" "dbyte_dmarc" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "_dmarc.dbyte.xyz"
  type    = "TXT"
  content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.dbyte_dkim
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["dbyte_dkim"]}"
}
resource "cloudflare_dns_record" "dbyte_dkim" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "*._domainkey.dbyte.xyz"
  type    = "TXT"
  content = "\"v=DKIM1; p=\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.i_dbyte_verification
  id = "${data.cloudflare_zones.dbyte.result[0].id}/${var.record_ids["i_dbyte_verification"]}"
}
resource "cloudflare_dns_record" "i_dbyte_verification" {
  zone_id = data.cloudflare_zones.dbyte.result[0].id
  name    = "i.dbyte.xyz"
  type    = "TXT"
  content = "\"google-site-verification=Cd0shXhD04dVDvFH2V7O_bwOB8RzjM_VZT3-9yqpyGk\""
  ttl     = 1
  proxied = false
}

# ---------------------------------------------------------------------------
# james-hackett.ie
# ---------------------------------------------------------------------------

import {
  to = cloudflare_dns_record.jh_apex
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_apex"]}"
}
resource "cloudflare_dns_record" "jh_apex" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "james-hackett.ie"
  type    = "A"
  content = var.relay_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_admin_photo
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_admin_photo"]}"
}
resource "cloudflare_dns_record" "jh_admin_photo" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "admin-photo.james-hackett.ie"
  type    = "CNAME"
  content = "photo.james-hackett.ie"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_docs
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_docs"]}"
}
# Third-party (GitHub Pages), unrelated to the relay.
resource "cloudflare_dns_record" "jh_docs" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "docs.james-hackett.ie"
  type    = "CNAME"
  content = "distrobyte.github.io"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_email_photo
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_email_photo"]}"
}
# Third-party (Mailgun), unrelated to the relay.
resource "cloudflare_dns_record" "jh_email_photo" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "email.photo.james-hackett.ie"
  type    = "CNAME"
  content = "eu.mailgun.org"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_pdk1
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_pdk1"]}"
}
resource "cloudflare_dns_record" "jh_pdk1" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "pdk1._domainkey.photo.james-hackett.ie"
  type    = "CNAME"
  content = "pdk1._domainkey.43abf.dkim2.eu.mgsend.org"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_pdk2
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_pdk2"]}"
}
resource "cloudflare_dns_record" "jh_pdk2" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "pdk2._domainkey.photo.james-hackett.ie"
  type    = "CNAME"
  content = "pdk2._domainkey.43abf.dkim2.eu.mgsend.org"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_photo
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_photo"]}"
}
resource "cloudflare_dns_record" "jh_photo" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "photo.james-hackett.ie"
  type    = "CNAME"
  content = "james-hackett.ie"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_scrapbook
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_scrapbook"]}"
}
resource "cloudflare_dns_record" "jh_scrapbook" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "scrapbook.james-hackett.ie"
  type    = "CNAME"
  content = "james-hackett.ie"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_www
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_www"]}"
}
resource "cloudflare_dns_record" "jh_www" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "www.james-hackett.ie"
  type    = "CNAME"
  content = "photo.james-hackett.ie"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_mx_b
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_mx_b"]}"
}
resource "cloudflare_dns_record" "jh_mx_b" {
  zone_id  = data.cloudflare_zones.james_hackett.result[0].id
  name     = "photo.james-hackett.ie"
  type     = "MX"
  content  = "mxb.eu.mailgun.org"
  priority = 10
  ttl      = 1
  proxied  = false
}

import {
  to = cloudflare_dns_record.jh_mx_a
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_mx_a"]}"
}
resource "cloudflare_dns_record" "jh_mx_a" {
  zone_id  = data.cloudflare_zones.james_hackett.result[0].id
  name     = "photo.james-hackett.ie"
  type     = "MX"
  content  = "mxa.eu.mailgun.org"
  priority = 10
  ttl      = 1
  proxied  = false
}

import {
  to = cloudflare_dns_record.jh_photo_dmarc
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_photo_dmarc"]}"
}
resource "cloudflare_dns_record" "jh_photo_dmarc" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "_dmarc.photo.james-hackett.ie"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:9381090@dmarc.mailgun.org,mailto:97c536f6@inbox.ondmarc.com; ruf=mailto:9381090@dmarc.mailgun.org,mailto:97c536f6@inbox.ondmarc.com;\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.jh_photo_spf
  id = "${data.cloudflare_zones.james_hackett.result[0].id}/${var.record_ids["jh_photo_spf"]}"
}
resource "cloudflare_dns_record" "jh_photo_spf" {
  zone_id = data.cloudflare_zones.james_hackett.result[0].id
  name    = "photo.james-hackett.ie"
  type    = "TXT"
  content = "\"v=spf1 include:mailgun.org ~all\""
  ttl     = 1
  proxied = false
}

# ---------------------------------------------------------------------------
# ihatenixos.org
# ---------------------------------------------------------------------------

import {
  to = cloudflare_dns_record.ihatenixos_apex
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_apex"]}"
}
resource "cloudflare_dns_record" "ihatenixos_apex" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "ihatenixos.org"
  type    = "A"
  content = var.relay_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.ihatenixos_wildcard
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_wildcard"]}"
}
# Same wildcard-to-relay pattern as *.dbyte.xyz — see note at top of file.
resource "cloudflare_dns_record" "ihatenixos_wildcard" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "*.ihatenixos.org"
  type    = "CNAME"
  content = "ihatenixos.org"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.ihatenixos_dmarc
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_dmarc"]}"
}
resource "cloudflare_dns_record" "ihatenixos_dmarc" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "_dmarc.ihatenixos.org"
  type    = "TXT"
  content = "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.ihatenixos_dkim
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_dkim"]}"
}
resource "cloudflare_dns_record" "ihatenixos_dkim" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "*._domainkey.ihatenixos.org"
  type    = "TXT"
  content = "v=DKIM1; p="
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.ihatenixos_verification
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_verification"]}"
}
resource "cloudflare_dns_record" "ihatenixos_verification" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "ihatenixos.org"
  type    = "TXT"
  content = "\"PiK3-7CadrAP4dMxDxQkF0KdkrDUV22Sv-S52PQizIU\""
  ttl     = 120
  proxied = false
}

import {
  to = cloudflare_dns_record.ihatenixos_spf
  id = "${data.cloudflare_zones.ihatenixos.result[0].id}/${var.record_ids["ihatenixos_spf"]}"
}
resource "cloudflare_dns_record" "ihatenixos_spf" {
  zone_id = data.cloudflare_zones.ihatenixos.result[0].id
  name    = "ihatenixos.org"
  type    = "TXT"
  content = "v=spf1 -all"
  ttl     = 1
  proxied = false
}

# ---------------------------------------------------------------------------
# crazybitta.biz
# ---------------------------------------------------------------------------

import {
  to = cloudflare_dns_record.crazybitta_apex
  id = "${data.cloudflare_zones.crazybitta.result[0].id}/${var.record_ids["crazybitta_apex"]}"
}
resource "cloudflare_dns_record" "crazybitta_apex" {
  zone_id = data.cloudflare_zones.crazybitta.result[0].id
  name    = "crazybitta.biz"
  type    = "A"
  content = var.relay_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.crazybitta_wildcard
  id = "${data.cloudflare_zones.crazybitta.result[0].id}/${var.record_ids["crazybitta_wildcard"]}"
}
# Same wildcard-to-relay pattern as *.dbyte.xyz — see note at top of file.
resource "cloudflare_dns_record" "crazybitta_wildcard" {
  zone_id = data.cloudflare_zones.crazybitta.result[0].id
  name    = "*.crazybitta.biz"
  type    = "CNAME"
  content = "crazybitta.biz"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.crazybitta_verification
  id = "${data.cloudflare_zones.crazybitta.result[0].id}/${var.record_ids["crazybitta_verification"]}"
}
resource "cloudflare_dns_record" "crazybitta_verification" {
  zone_id = data.cloudflare_zones.crazybitta.result[0].id
  name    = "crazybitta.biz"
  type    = "TXT"
  content = "\"jshmO2YG7mJlYvQJv7Jr3Z3nHdk-BbS3fnXfEUBUDAc\""
  ttl     = 120
  proxied = false
}

# ---------------------------------------------------------------------------
# nicecocks.biz
# ---------------------------------------------------------------------------

import {
  to = cloudflare_dns_record.nicecocks_apex
  id = "${data.cloudflare_zones.nicecocks.result[0].id}/${var.record_ids["nicecocks_apex"]}"
}
resource "cloudflare_dns_record" "nicecocks_apex" {
  zone_id = data.cloudflare_zones.nicecocks.result[0].id
  name    = "nicecocks.biz"
  type    = "A"
  content = var.relay_ipv4
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.nicecocks_dmarc
  id = "${data.cloudflare_zones.nicecocks.result[0].id}/${var.record_ids["nicecocks_dmarc"]}"
}
resource "cloudflare_dns_record" "nicecocks_dmarc" {
  zone_id = data.cloudflare_zones.nicecocks.result[0].id
  name    = "_dmarc.nicecocks.biz"
  type    = "TXT"
  content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.nicecocks_dkim
  id = "${data.cloudflare_zones.nicecocks.result[0].id}/${var.record_ids["nicecocks_dkim"]}"
}
resource "cloudflare_dns_record" "nicecocks_dkim" {
  zone_id = data.cloudflare_zones.nicecocks.result[0].id
  name    = "*._domainkey.nicecocks.biz"
  type    = "TXT"
  content = "\"v=DKIM1; p=\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.nicecocks_spf
  id = "${data.cloudflare_zones.nicecocks.result[0].id}/${var.record_ids["nicecocks_spf"]}"
}
resource "cloudflare_dns_record" "nicecocks_spf" {
  zone_id = data.cloudflare_zones.nicecocks.result[0].id
  name    = "nicecocks.biz"
  type    = "TXT"
  content = "\"v=spf1 -all\""
  ttl     = 1
  proxied = false
}
