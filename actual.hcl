job "actual" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 5006
      }
    }

    service {
      name = "actual"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.port=${NOMAD_PORT_http}",
        "traefik.docker.network=traefik_web",
        "traefik.http.routers.actual.rule=Host(`actual.dbyte.xyz`)",
        "traefik.http.routers.actual.tls=true",
        "traefik.http.routers.actual.tls.certresolver=lets-encrypt",
      ]
    }

    task "actual" {
      driver = "docker"

      config {
	image = "jlongster/actual-server"
	ports = ["http"]
	#volumes = [
	#  "/data/actual/server:/app/server-files",
        #  "/data/actual/user:/app/user-files"
	#]
      }
    }
  }
}
