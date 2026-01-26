id          = "immich-homes"
name        = "immich-homes"
type        = "csi"
plugin_id   = "synology"

capacity_min = "30GiB"
capacity_max = "38GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime", "soft", "async"]
}

parameters {
  location = "/volume1"
}
