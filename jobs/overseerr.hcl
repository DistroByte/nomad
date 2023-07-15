job "overseerr" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 5055
      }
    }

    service {
      name = "overseerr"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.overseerr.rule=Host(`request.dbyte.xyz`)",
	"traefik.http.routers.overseerr.entrypoints=websecure",
	"traefik.http.routers.overseerr.tls=true",
	"traefik.http.routers.overseerr.tls.certresolver=lets-encrypt"
      ]
    }

    task "overseerr" {
      driver = "docker"

      config {
        image = "sctx/overseerr:latest"
	ports = ["http"]

	mount {
	  type = "bind"
          target = "/app/config"
          source = "/data/overseerr"
          readonly = false
	}
      }

      resources {
        cpu = 200
        memory = 600
      }
    }
  }
}
