job "ghost" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 2368
      }
      port "metrics" {
        to = 8081
      }
    }


    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 1000
    }

    service {
      name = "ghost"
      port = "http"

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ghost.rule=Host(`photos.james-hackett.ie`) || Host(`ghost.james-hackett.ie`)",
      ]
    }

    task "website" {
      driver = "docker"

      config {
        image = "ghost:latest"
        ports = ["http"]

        mount {
          type = "bind"
          source = "..${NOMAD_ALLOC_DIR}/data/"
          target = "/var/lib/ghost/content/"
          readonly = false
        }
      }

      env {
        url = "https://photos.james-hackett.ie"
        admin__url = "https://ghost.james-hackett.ie"
        database__client = "sqlite3"
        database__connection__filename = "${NOMAD_ALLOC_DIR}/data/ghost.db"
        logging__level = "info"
        logging__transports = "[\"stdout\"]"
        privacy__useTinfoil = "true"
      }
    }
  }
}
