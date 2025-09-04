job "jellyseerr" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 5055
      }
    }

    service {
      name = "jellyseerr"
      port = "http"

      check {
        type     = "http"
        path     = "/api/v1/status"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jellyseerr.rule=Host(`request.dbyte.xyz`)",
      ]
    }

    task "jellyseerr" {
      driver = "docker"

      config {
        image = "fallenbagel/jellyseerr:latest"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/app/config"
          source   = "/data/jellyseerr/config"
          readonly = false
        }
      }

      env {
        LOG_LEVEL = "info"
      }

      resources {
        cpu    = 200
        memory = 600
      }
    }
  }
}
