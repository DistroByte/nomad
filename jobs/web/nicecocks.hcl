job "nicecocks" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "nicecocks"
      port = "http"

      check {
        type     = "http"
        path     = "/index.html"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nicecocks.rule=Host(`nicecocks.biz`)",
        "icon=https://nicecocks.biz/favicon.ico"
      ]
    }

    task "nicecocks" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/nicecocks.biz/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
