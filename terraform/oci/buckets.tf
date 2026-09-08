data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# Optional second backup copy (`restic copy` from the primary B2 repo).
# Created now, unused until wired up — see docs/Disaster-Recovery.md for why
# B2 is the primary: backups must survive this Oracle account disappearing.
resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "homelab-backups"
  versioning     = "Disabled"
}
