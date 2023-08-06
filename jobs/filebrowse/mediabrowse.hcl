job "mediashare" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 80
      }
    }

    service {
      name = "mediashare"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.mediashare.rule=Host(`share.dbyte.xyz`)",
	"traefik.http.routers.mediashare.entrypoints=websecure",
	"traefik.http.routers.mediashare.tls=true",
	"traefik.port=${NOMAD_PORT_http}",
	"traefik.http.routers.mediashare.tls.certresolver=lets-encrypt",
	"traefik.frontend.passHostHeader=true",
	"traefik.http.routers.mediashare.middlewares=auth",
	"traefik.http.middlewares.auth.basicauth.users=share:$apr1$0QNuLBe0$.Emmh/KSVYHXJtLPtj2CW.",
      ]
    }

    task "mediashare" {
      driver = "docker"

      config {
        image = "ghcr.io/distrobyte/nginx-file-browser:share"
	ports = ["http"]

	mount {
	  type = "bind"
          target = "/opt/www/files/Movies"
          source = "/media/nas/movies"
          readonly = false
	}
	
	mount {
	  type = "bind"
          target = "/opt/www/files/TV"
          source = "/media/nas/tv"
          readonly = false
	}
      }

      resources {
        memory = 50
      }
    }
  }
}
