job "mumble" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "voice" {
    network {
      port "voice-udp" {
        to = 64738
      }
    }

    service {
      port = "voice-udp"

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
      shutdown_delay = "5s"

      config {
        image      = "mumblevoip/mumble-server:latest"
        force_pull = true
        ports      = ["voice-udp"]

        hostname = "mumble.dbyte.xyz"
        #hostname = "hermes.internal"
      }

      template {
        data        = <<EOF
MUMBLE_SUPERUSER_PASSWORD={{ key "mumble/admin/password" }}
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
