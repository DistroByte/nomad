job "gerry" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "bot" {
    network {
      port "http" {
        to = 8080
      }
    }

    volume "gerry-data" {
      type            = "csi"
      read_only       = false
      source          = "gerry"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "gerry"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.gerry.rule=Host(`gerry.dbyte.xyz`)",
      ]
    }

    task "gerry" {
      driver = "docker"

      config {
        image = "ghcr.io/distrobyte/gerry:0.5.2"
        ports = ["http"]
      }

      volume_mount {
        volume      = "gerry-data"
        destination = "/app"
        read_only   = false
      }

      template {
        data        = <<EOF
PROD=true
EOF
        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 100
      }
    }
  }
}
