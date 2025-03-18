job "grafana" {
  datacenters = ["dc1"]

  group "grafana" {
    network {
      port "http" {}
    }

    volume "grafana-lib" {
      type            = "csi"
      source          = "grafana-lib"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    task "grafana" {
      driver = "docker"
      user = "0"

      config {
        image = "grafana/grafana-oss"
        ports = ["http"]
      }
      
      template {
        data = <<EOH
GF_FEATURE_TOGGLES_ENABLE=publicDashboards
GF_SERVER_HTTP_PORT={{ env "NOMAD_PORT_http" }}
GF_INSTALL_PLUGINS=grafana-piechart-panel
GF_SERVER_ROOT_URL="https://grafana.dbyte.xyz"
EOH
        destination = "local/file.env"
        env         = true
      }

      volume_mount {
        volume      = "grafana-lib"
        destination = "/var/lib/grafana"
      }

      resources {
        cpu    = 100
        memory = 300
      }

      service {
        name = "grafana"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.rule=Host(`grafana.dbyte.xyz`)",
        ]

        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"

          success_before_passing   = "3"
          failures_before_critical = "3"

          check_restart {
            limit = 3
            grace = "60s"
          }
        }
      }
    }
  }
}
