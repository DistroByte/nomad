job "ihatenixos" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "ihatenixos"
      port = "http"

      check {
        type     = "http"
        path     = "/index.html"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ihatenixos.rule=Host(`ihatenixos.org`)",
        "traefik.http.routers.ihatenixos.entrypoints=websecure",
        "traefik.http.routers.ihatenixos.tls.certresolver=lets-encrypt",
	"prometheus.io/scrape=false"
      ]
    }

    task "ihatenixos" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/ihatenixos.org/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
