id          = "immich-data"
name        = "immich-data"
type        = "csi"
plugin_id   = "synology"

capacity_min = "5GiB"
capacity_max = "8GiB"

capability {
  access_mode     = "multi-node-multi-writer" # multi-node, both api server and worker tasks
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime", "soft", "async"]
}

parameters {
  location = "/volume1"
}
