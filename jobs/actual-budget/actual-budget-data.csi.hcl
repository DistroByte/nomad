id          = "actual-budget"
name        = "actual-budget"
type        = "csi"
plugin_id   = "synology"

capacity_min = "5GiB"
capacity_max = "10GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime"]
}

parameters {
  location = "/volume1"
}
