job "collegeshare" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 80
      }
    }

    service {
      name = "collegeshare"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.collegeshare.rule=Host(`college.dbyte.xyz`)",
	"traefik.http.routers.collegeshare.entrypoints=websecure",
	"traefik.http.routers.collegeshare.tls=true",
	"traefik.port=${NOMAD_PORT_http}",
	"traefik.http.routers.collegeshare.tls.certresolver=lets-encrypt",
	"traefik.frontend.passHostHeader=true",
	"traefik.http.routers.collegeshare.middlewares=auth",
	"traefik.http.middlewares.auth.basicauth.users=share:$apr1$0QNuLBe0$.Emmh/KSVYHXJtLPtj2CW.",
      ]
    }

    task "collegeshare" {
      driver = "docker"

      config {
        image = "mohamnag/nginx-file-browser:latest"
	ports = ["http"]

	mount {
	  type = "bind"
          target = "/opt/www/files/"
          source = "/media/college"
          readonly = false
	}
      }
    }
  }
}
