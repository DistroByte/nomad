job "crazybittabiz" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "crazybittabiz"
      port = "http"

      check {
        type     = "http"
        path     = "/index.html"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.crazybittabiz.rule=Host(`crazybitta.biz`)",
      ]
    }

    task "crazybittabiz" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image      = "nginx:latest"
        force_pull = true
        ports      = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/crazybittabiz/site"
          readonly = true
        }
      }

      resources {
        cpu    = 100
        memory = 50
      }
    }
  }
}
