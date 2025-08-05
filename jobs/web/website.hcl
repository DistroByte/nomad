job "website" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "website"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.website.rule=Host(`james-hackett.ie`)",
        "icon=https://james-hackett.ie/profile.webp",
      ]
    }

    task "website" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/website/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
