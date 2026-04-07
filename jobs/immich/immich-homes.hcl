plugin_id   = "nfs"
type        = "csi"
id          = "immich-homes"
name        = "Immich Homes"

capability {
  access_mode = "multi-node-multi-writer"
	// access_mode = "single-node-reader-only"
	attachment_mode = "file-system"
}

context {
  server = "dionysus.internal"
  share = "/volume1/homes"
  mountPermissions = "0"
}

mount_options {
  fs_type = "nfs"
  mount_flags = [ "soft", "async" ]
}