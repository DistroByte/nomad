job "molecule" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "server" {
    update {
      max_parallel      = 1
      canary            = 1
      min_healthy_time  = "20s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
    }

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

      config {
        image = "ghcr.io/distrobyte/molecule:0.9.3"
        ports = ["http"]

        mount {
          type   = "bind"
          source = "local/config.yaml"
          target = "/config.yaml"
        }
      }

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
  - service: "photos"
    url: "https://photos.dbyte.xyz"
    icon: "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/png/synology-photos.png"
  - service: "drive"
    url: "https://drive.dbyte.xyz"
    icon: "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/png/synology-drive.png"
  - service: "jellyfin"
    url: "https://video.dbyte.xyz"
  - service: "ghost"
    url: "https://admin-photo.james-hackett.ie/ghost"
  - service: "sonarr"
    url: "http://dionysus.internal:8989"
  - service: "radarr"
    url: "http://dionysus.internal:7878"
  - service: "pihole"
    url: "https://dionysus.internal/admin"
    icon: "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/png/pi-hole.png"
  - service: "jackett"
    url: "http://dionysus.internal:9117"
  - service: "syncthing"
    url: "http://dionysus.internal:8384"

nomad:
  address: "http://zeus.internal:4646"
EOF
        destination = "local/config.yaml"
      }

      resources {
        cpu    = 200
        memory = 50
      }
    }
  }
}
