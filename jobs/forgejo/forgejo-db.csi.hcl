id        = "forgejo-db"
name      = "forgejo-db"
type      = "csi"
plugin_id = "synology"

capacity_min = "1GiB"
capacity_max = "5GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

#mount/fstab options https://linux.die.net/man/8/mount
mount_options {
  fs_type     = "btrfs"
  mount_flags = ["noatime"]
}

parameters {
  location = "/volume1"
}
