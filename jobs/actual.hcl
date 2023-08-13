job "actual" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 5006
      }
    }

    update {
      max_parallel = 1
      canary = 1
      auto_promote = false
      auto_revert = true
      min_healthy_time = "30s"
      healthy_deadline = "2m"
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
        "traefik.http.routers.actual.rule=Host(`actual.dbyte.xyz`, `${NOMAD_SHORT_ALLOC_ID}.dbyte.xyz`)",
        "traefik.http.routers.actual.tls=true",
        "traefik.http.routers.actual.tls.certresolver=lets-encrypt",
      ]
    }

    task "actual" {
      driver = "docker"


      config {
	image = "actualbudget/actual-server:23.8.1"
	ports = ["http"]
      }

      resources {
	cpu = 100
	memory = 400
      }
    }
  }
}
