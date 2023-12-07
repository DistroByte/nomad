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
        "traefik.port=${NOMAD_PORT_http}",
        "traefik.http.routers.shlink.rule=Host(`s.dbyte.xyz`)",
        "traefik.http.routers.shlink.tls=true",
        "traefik.http.routers.shlink.tls.certresolver=lets-encrypt",
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
DB_DRIVER=postgres
DB_USER={{ key "shlink/db/user" }}
DB_PASSWORD={{ key "shlink/db/pass" }}
DB_NAME={{ key "shlink/db/name" }}
DB_HOST=postgresql.service.consul
GEOLITE_LICENSE_KEY={{ key "shlink/geolite/key" }}
EOH

        destination = "local/file.env"
        env         = true
      }
      resources {
        memory = 500 # 6gb
      }
    }
  }
}
