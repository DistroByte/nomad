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
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.actual.rule=Host(`actual.dbyte.xyz`)",
        "traefik.http.routers.actual.tls=true",
        "traefik.http.routers.actual.tls.certresolver=lets-encrypt",
	"prometheus.io/scrape=false"
      ]
    }

    task "actual" {
      driver = "docker"


      config {
        image = "actualbudget/actual-server:24.1.0"
        ports = ["http"]
      }

      template {
        data = <<EOF
ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB=500
DEBUG=debug:config
EOF
        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 700
        memory = 600
      }
    }
  }
}
