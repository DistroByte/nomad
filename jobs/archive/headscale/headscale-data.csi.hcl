id          = "headscale"
name        = "headscale"
type        = "csi"
external_id = "3f42c9c2-a361-4c1c-af16-ee85b940e69a"
plugin_id   = "synology"

capacity_min = "1GiB"
capacity_max = "2GiB"

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
