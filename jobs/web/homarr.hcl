job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

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
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.homarr.rule=Host(`home.dbyte.xyz`)",
      ]
    }

    task "homarr" {
      driver = "docker"

      config {
        image = "ghcr.io/ajnart/homarr:latest"
        ports = ["http"]

        volumes = [
          "/data/homarr/configs:/app/data/configs",
          "/data/homarr/icons:/app/public/icons",
          "/data/homarr/img:/app/public/img"
        ]
      }

      resources {
        cpu    = 300
        memory = 500
      }
    }
  }
}
