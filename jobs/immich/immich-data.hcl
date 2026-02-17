id          = "immich-data"
name        = "immich-data"
type        = "csi"
plugin_id   = "nfs"

capability {
  access_mode = "multi-node-multi-writer"
	// access_mode = "single-node-reader-only"
	attachment_mode = "file-system"
}

context {
  server = "dionysus.internal"
  share = "/volume1/data"
  subDir = "immich"
  mountPermissions = "0"
}

mount_options {
  fs_type = "nfs"
  mount_flags = [ "soft", "async" ]
}
