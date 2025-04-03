job "scratch" {
  datacenters = ["dc1"]
  type        = "service"

  group "group" {
    volume "scratch" {
      type      = "csi"
      source    = "gerry"
      read_only = false
      attachment_mode = "file-system"
      access_mode = "single-node-writer"
    }

    count = 1

    task "2001" {
      driver = "docker"
      user = "0:0"

      config {
        image   = "alpine:latest"
        command = "/bin/sh"
        args    = ["-c", "while true; do sleep 500; done"]
      }

      volume_mount {
        volume      = "scratch"
        destination = "/scratch"
      }
    }
  }
}
