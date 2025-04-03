job "photo" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 2368
      }
      port "metrics-http" {
        to = 8081
      }
    }

    volume "photo-data" {
      type            = "csi"
      read_only       = false
      source          = "photo"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "photo"
      port = "http"

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.photo.rule=Host(`photo.james-hackett.ie`) || Host(`admin-photo.james-hackett.ie`)",
      ]
    }

    task "website" {
      driver = "docker"

      config {
        image = "ghost:latest"
        ports = ["http"]
      }

      volume_mount {
        volume      = "photo-data"
        destination = "/var/lib/ghost/content"
        read_only   = false
      }

      env {
        url = "https://photo.james-hackett.ie"
        admin__url = "https://admin-photo.james-hackett.ie"
        database__client = "sqlite3"
        database__connection__filename = "/var/lib/ghost/content/data/ghost.db"
        logging__level = "info"
        logging__transports = "[\"stdout\"]"
        privacy__useTinfoil = "true"
        mail__from = "support@distrobyte.io"
      }

      resources {
        cpu    = 600
        memory = 1000
      }
    }
  }
}
