job "homarr" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 7575
      }
    }

    service {
      name = "homarr"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.homarr.rule=Host(`home.dbyte.xyz`)",
	"traefik.http.routers.homarr.entrypoints=websecure",
	"traefik.http.routers.homarr.tls=true",
	"traefik.http.routers.homarr.tls.certresolver=lets-encrypt"
      ]
    }

    task "homarr" {
      driver = "docker"

      config {
        image = "ghcr.io/ajnart/homarr:latest"
	ports = ["http"]

	mount {
	  type = "bind"
          target = "/app/data/configs"
          source = "/data/homarr/configs"
          readonly = false
	}

	mount {
	  type = "bind"
          target = "/app/public/icons"
          source = "/data/homarr/icons"
          readonly = false
	}

	mount {
	  type = "bind"
          target = "/app/public/img"
          source = "/data/homarr/img"
          readonly = false
	}
      }
    }
  }
}
