job "pinting" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "pinting"
      port = "http"

      check {
        type     = "http"
        path     = "/index.html"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.pinting.rule=Host(`pint.ing`)",
        "traefik.http.routers.pinting.entrypoints=websecure",
        "traefik.http.routers.pinting.tls.certresolver=lets-encrypt"
      ]
    }

    task "pinting" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/pinting/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
