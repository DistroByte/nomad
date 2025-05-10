job "shlink" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "shlink"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.shlink.rule=Host(`s.dbyte.xyz`)",
      ]
    }

    task "shlink" {
      driver = "docker"

      config {
        image = "shlinkio/shlink"
        ports = ["http"]
      }

      template {
        data = <<EOH
DEFAULT_DOMAIN=s.dbyte.xyz
IS_HTTPS_ENABLED=true
GEOLITE_LICENSE_KEY={{ key "shlink/geolite/key" }}
EOH

        destination = "local/file.env"
        env         = true
      }
      resources {
        memory = 500
      }
    }
  }
}
