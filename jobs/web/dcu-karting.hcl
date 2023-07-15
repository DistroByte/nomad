job "dcu-karting" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 80
      }
    }

    service {
      name = "dcu-karting"
      port = "http"

      check {
        type = "http"
        path = "/index.html"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.dcu-karting.rule=Host(`karting.crazybitta.biz`)",
	"traefik.http.routers.dcu-karting.entrypoints=websecure",
	"traefik.http.routers.dcu-karting.tls.certresolver=lets-encrypt"
      ]
    }

    task "dcu-karting" {
      driver = "docker"

      config {
        image = "ghcr.io/redbrick/karting"
	ports = ["http"]
      }
    }
  }
}
