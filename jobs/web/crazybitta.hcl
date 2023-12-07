job "crazybittabiz" {
  datacenters = ["dc1"]
  type        = "service"

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
        "traefik.http.routers.crazybittabiz.entrypoints=websecure",
        "traefik.http.routers.crazybittabiz.tls.certresolver=lets-encrypt"
      ]
    }

    task "crazybittabiz" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/crazybittabiz/site"
          readonly = true
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
