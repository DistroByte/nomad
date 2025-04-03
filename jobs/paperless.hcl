job "paperless" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    version = 1
  }

  group "paperless-web" {
    network {
      port "http" {
        static = 8067
      }
      port "redis" {
        to = 6379
      }
    }

    volume "paperless-data" {
      type            = "csi"
      read_only       = false
      source          = "paperless"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "paperless"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "15s"
        timeout  = "5s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.paperless.rule=Host(`paperless.dbyte.xyz`)",
        "traefik.http.middlewares.paperless.headers.contentSecurityPolicy=default-src 'self'; img-src 'self' data:"
      ]
    }

    task "paperless-webserver" {
      driver = "docker"

      env {
        PAPERLESS_REDIS  = "redis://${NOMAD_ADDR_redis}"
        PAPERLESS_PORT   = "${NOMAD_PORT_http}"
      }

      config {
        image = "ghcr.io/paperless-ngx/paperless-ngx:latest"
        ports = ["http"]
      }

      volume_mount {
        volume      = "paperless-data"
        destination = "/data"
        read_only   = false
      }

      template {
        data = <<EOH
PAPERLESS_SECRETKEY={{ key "paperless/env/secret" }}
PAPERLESS_URL={{ key "paperless/env/url" }}
PAPERLESS_ADMIN_USER={{ key "paperless/admin/user" }}
PAPERLESS_ADMIN_PASSWORD={{ key "paperless/admin/password" }}
PAPERLESS_PRE_CONSUME_SCRIPT="/data/preconsume"
PAPERLESS_CONSUMPTION_DIR="/data/consume"
PAPERLESS_DATA_DIR="/data/data"
PAPERLESS_EMPTY_TRASH_DIR="/data/trash"
PAPERLESS_MEDIA_ROOT="/data/media"
PAPERLESS_ALLOWED_HOSTS="localhost,192.168.0.4,192.168.0.3,paperless.dbyte.xyz"
PAPERLESS_CONSUMER_POLLING=0
PAPERLESS_TIME_ZONE=Europe/Dublin
EOH

        destination = "local/file.env"
        env         = true
      }

      resources {
        cpu    = 800
        memory = 1000
      }
    }

    task "paperless-broker" {
      driver = "docker"

      config {
        image = "docker.io/library/redis:7"
        ports = ["redis"]
      }
      
      resources {
        cpu    = 300
        memory = 50
      }
    }
  }
}
