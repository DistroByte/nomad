id        = "immich-postgres-backup"
name      = "immich-postgres-backup"
type      = "csi"
plugin_id = "nfs"

capability {
  access_mode     = "multi-node-multi-writer"
  attachment_mode = "file-system"
}

context {
  server           = "dionysus.internal"
  share            = "/volume1/data"
  subDir           = "immich-postgres-backup"
  mountPermissions = "0"
}

mount_options {
  fs_type     = "nfs"
  mount_flags = ["soft", "async"]
}
