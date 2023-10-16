job "grafana" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
	to = 3000
      }
    }

    service {
      name = "grafana"
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
        "traefik.http.routers.actual.rule=Host(`grafana.dbyte.xyz`)",
        "traefik.http.routers.actual.tls=true",
        "traefik.http.routers.actual.tls.certresolver=lets-encrypt",
      ]
    }

    task "grafana" {
      driver = "docker"

      env {
	GF_AUTH_BASIC_ENABLED = "false"
	GF_INSTALL_PLUGINS = "grafana-piechart-panel"
	GF_SERVER_ROOT_URL = "https://grafana.dbyte.xyz"
#	GF_DATABASE_URL = "postgres://
      }

      config {
        image = "grafana/grafana"
	ports = ["http"]

#	volumes = [
#	  "/data/grafana/:/var/lib/grafana"
#	]
      }
    }

  }
}

