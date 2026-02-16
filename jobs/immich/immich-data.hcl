id          = "immich-data"
name        = "immich-data"
external_id = "cf832e1d-f872-433d-8a1b-4a7120cee56c"
type        = "csi"
plugin_id   = "synology"

capacity_min = "10GiB"
capacity_max = "18GiB"

capability {
  access_mode     = "multi-node-multi-writer" # multi-node, both api server and worker tasks
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime", "async"]
}

parameters {
  location = "/volume1"
}
