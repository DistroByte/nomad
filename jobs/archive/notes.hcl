job "notes" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "notes"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.notes.rule=Host(`notes.dbyte.xyz`)",
      ]
    }

    task "notes" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/notes/export"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
