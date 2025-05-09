job "distro-vm" {
  datacenters = ["dc1"]

  group "distro-vm" {

    network {
      mode = "host"
    }

    service {
      name = "distro-vm"
    }

    task "distro-vm" {
      constraint {
        attribute = "${attr.unique.hostname}"
        value     = "hermes"
      }

      resources {
        cpu    = 1200
        memory = 400
      }

      artifact {
        source      = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
        destination = "local/distro-vm.qcow2"
        mode        = "file"
      }

      driver = "qemu"

      config {
        image_path = "local/distro-vm.qcow2"

        accelerator = "kvm"

        drive_interface = "virtio"

        args = [
          "-netdev",
          "bridge,id=hn0",
          "-device",
          "virtio-net-pci,netdev=hn0,id=nic1,mac=52:54:84:ba:49:01",
          "-smbios",
          "type=1,serial=ds=nocloud-net;s=http://192.168.1.3:8090/distro-vm/",
	]
      }
    }
  }
}

