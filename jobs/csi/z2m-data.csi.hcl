id        = "z2m"
name      = "z2m"
type      = "csi"
plugin_id = "synology"

capacity_min = "2GiB"
capacity_max = "4GiB"

capability {
  access_mode = "single-node-writer"
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