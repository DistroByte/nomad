job "fileshare" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 80
      }
    }

    service {
      name = "fileshare"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.fileshare.rule=Host(`share.dbyte.xyz`)",
	"traefik.http.routers.fileshare.entrypoints=websecure",
	"traefik.http.routers.fileshare.tls=true",
	"traefik.port=${NOMAD_PORT_http}",
	"traefik.http.routers.fileshare.tls.certresolver=lets-encrypt",
	"traefik.frontend.passHostHeader=true",
	"traefik.http.routers.fileshare.middlewares=auth",
	"traefik.http.middlewares.auth.basicauth.users=share:$apr1$0QNuLBe0$.Emmh/KSVYHXJtLPtj2CW.",
      ]
    }

    task "fileshare" {
      driver = "docker"

      config {
        image = "mohamnag/nginx-file-browser:latest"
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
    }
  }
}
