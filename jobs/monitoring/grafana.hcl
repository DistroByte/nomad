job "grafana" {
  datacenters = ["dc1"]

  type = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

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
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.port=${NOMAD_PORT_http}",
        "traefik.docker.network=traefik_web",
        "traefik.http.routers.grafana.rule=Host(`grafana.dbyte.xyz`)",
        "traefik.http.routers.grafana.tls=true",
        "traefik.http.routers.grafana.tls.certresolver=lets-encrypt",
      ]
    }

    task "grafana" {
      driver = "docker"

      env {
        GF_AUTH_BASIC_ENABLED = "false"
        GF_INSTALL_PLUGINS    = "grafana-piechart-panel"
        GF_SERVER_ROOT_URL    = "https://grafana.dbyte.xyz"
      }

      config {
        image = "grafana/grafana"
        ports = ["http"]

        volumes = [
          "/data/grafana/:/var/lib/grafana"
        ]
      }


      template {
        data = <<EOH
GF_DATABASE_TYPE=postgres
GF_DATABASE_HOST=postgresql.service.consul
GF_DATABASE_NAME=grafana
GF_DATABASE_USER={{ key "grafana/db/user" }}
GF_DATABASE_PASSWORD={{ key "grafana/db/pass" }}
GF_FEATURE_TOGGLES_ENABLE=publicDashboards
EOH

        destination = "local/file.env"
        env         = true
      }
    }

  }
}

