id          = "immich-homes"
name        = "immich-homes"
external_id = "92346fcb-f9be-474c-97ec-0a6c61050d14"
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
  mount_flags = ["noatime", "async"]
}

parameters {
  location = "/volume1"
}
