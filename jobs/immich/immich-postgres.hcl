id          = "immich-postgres"
name        = "immich-postgres"
type        = "csi"
plugin_id   = "synology"

capacity_min = "5GiB"
capacity_max = "8GiB"

capability {
  access_mode     = "single-node-single-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime", "soft", "async"]
}

parameters {
  location = "/volume1"
}
