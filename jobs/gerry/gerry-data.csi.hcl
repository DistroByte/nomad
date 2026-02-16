id          = "gerry"
name        = "gerry"
external_id = "802795ba-7ba1-47b9-97e7-c05158b90c67"
type        = "csi"
plugin_id   = "synology"

capacity_min = "6GiB"
capacity_max = "10GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

#mount/fstab options https://linux.die.net/man/8/mount
mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime"]
}

#if you have multiple storage pools and/or volumes, specify where to mount the container volume/LUN or else it'll just pick one for you
parameters {
  location = "/volume1"
}
