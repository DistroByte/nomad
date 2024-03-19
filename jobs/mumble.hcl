job "mumble" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "voice" {
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
	"prometheus.io/scrape=false"
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
MUMBLE_SUPERUSER_PASSWORD="JaNLNcEwaetq"
MUMBLE_CONFIG_WELCOMETEXT="Ahh! SuperNintendo Chalmers!"
MUMBLE_CONFIG_ALLOWHTML=true
EOF
        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 300
        memory = 100
      }
    }
  }
}
