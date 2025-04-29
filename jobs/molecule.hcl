job "molecule" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "server" {
    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "molecule"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.molecule.rule=Host(`molecule.dbyte.xyz`)",
      ]
    }

    task "molecule" {
      driver = "docker"

      template {
        data        = <<EOF
PROD=true
API_KEY={{ key "molecule/apikey" }}
CONFIG_FILE="/config.yaml"
EOF
        destination = "local/env"
        env         = true
      }

      template {
        data        = <<EOF
standard_urls:
  - service: "nomad"
    url: "http://zeus.internal:4646"
  - service: "consul"
    url: "http://zeus.internal:8500"
  - service: "traefik"
    url: "http://hermes.internal:8081"
  - service: "synology-dsm"
    url: "https://dionysus.internal:5001"
  - service: "plausible"
    url: "https://plausible.dbyte.xyz"
  - service: "photos"
    url: "https://photos.dbyte.xyz"
  - service: "drive"
    url: "https://drive.dbyte.xyz"
  - service: "plex"
    url: "https://video.dbyte.xyz"
  - service: "ghost"
    url: "https://admin-photo.james-hackett.ie/ghost"

nomad:
  address: "http://zeus.internal:4646"
EOF
        destination = "local/config.yaml"
      }

      config {
        image = "ghcr.io/distrobyte/molecule:latest"
        ports = ["http"]

        mount {
          type   = "bind"
          source = "local/config.yaml"
          target = "/config.yaml"
        }

      }
      
      resources {
        cpu    = 200
        memory = 100
      }
    }
  }
}
