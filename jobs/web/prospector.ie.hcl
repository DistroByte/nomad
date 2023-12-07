job "prospector.ie" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "prospector"
      port = "http"

      check {
        type     = "http"
        path     = "/index.html"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.prospector.rule=Host(`prospector.ie`)",
        "traefik.http.routers.prospector.entrypoints=websecure",
        "traefik.http.routers.prospector.tls.certresolver=lets-encrypt"
      ]
    }

    task "prospector.ie" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/prospector.ie/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
