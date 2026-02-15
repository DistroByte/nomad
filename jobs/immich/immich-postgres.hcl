id          = "immich-postgres"
name        = "immich-postgres"
external_id = "407e83c4-fc62-4083-8a67-64e7efc828c0"
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
