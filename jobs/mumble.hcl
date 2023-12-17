job "mumble" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "web" {
    network {
      port "voice" {
        to = 64738
      }
    }

    service {
      port = "voice"

      tags = [
        "traefik.enable=true",
        "traefik.tcp.routers.mumble-tcp.rule=HostSNI(`mumble.dbyte.xyz`)",
        "traefik.tcp.routers.mumble-tcp.tls.passthrough=true",
        "traefik.tcp.routers.mumble-tcp.entrypoints=voice-tcp",
        "traefik.udp.routers.mumble-udp.entrypoints=voice-udp",
      ]
    }

    task "mumble" {
      driver = "docker"

      config {
        image = "mumblevoip/mumble-server:latest"
        ports = ["voice"]

        hostname = "mumble.dbyte.xyz"
      }

      template {
        data        = <<EOF

EOF
        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 300
        memory = 500
      }
    }
  }
}
