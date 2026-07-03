id          = "actual-budget"
name        = "actual-budget"
external_id = "9c2fe417-387b-4f32-9b00-790a78956b11"
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
