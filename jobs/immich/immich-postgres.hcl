id          = "immich-postgres"
name        = "immich-postgres"
external_id = "220a342f-293b-407f-9303-fddd19f37ea9"
type        = "csi"
plugin_id   = "synology"

capacity_min = "5GiB"
capacity_max = "8GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime", "async"]
}

parameters {
  location = "/volume1"
}
