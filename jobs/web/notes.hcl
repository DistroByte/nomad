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

      #check {
      #  type     = "http"
      #  path     = "/blog/redbrick-maintenance-with-nomad.html"
      #  interval = "10s"
      #  timeout  = "2s"
      #}

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.notes.rule=Host(`notes.dbyte.xyz`)",
        "traefik.http.routers.notes.entrypoints=websecure",
        "traefik.http.routers.notes.tls.certresolver=lets-encrypt",
	"prometheus.io/scrape=false"
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
