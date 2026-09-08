job "paperless" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
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
      driver         = "docker"
      shutdown_delay = "5s"

      env {
        PAPERLESS_REDIS = "redis://${NOMAD_ADDR_redis}"
        PAPERLESS_PORT  = "${NOMAD_PORT_http}"
      }

      config {
        image      = "ghcr.io/paperless-ngx/paperless-ngx:2.20.13"
        force_pull = true
        ports      = ["http"]
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
        cpu    = 400
        memory = 1000
      }
    }

    # Companion rather than a separate periodic job: the CSI volume is
    # single-node-writer, so only a task in this group can reach the live data.
    # document_exporter produces a portable full export (documents + sqlite
    # metadata) that restores with document_importer on any instance.
    task "exporter" {
      driver = "docker"

      config {
        image        = "ghcr.io/paperless-ngx/paperless-ngx:2.20.13"
        entrypoint   = ["/bin/sh"]
        args         = ["/local/export-loop.sh"]
        network_mode = "host"

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups/paperless"
        }
      }

      volume_mount {
        volume      = "paperless-data"
        destination = "/data"
        read_only   = false
      }

      template {
        data = <<EOH
PAPERLESS_DATA_DIR="/data/data"
PAPERLESS_MEDIA_ROOT="/data/media"
PAPERLESS_SECRETKEY={{ key "paperless/env/secret" }}
HEARTBEAT_TOKEN={{ key "gatus/heartbeat-token" }}
EOH

        destination = "secrets/exporter.env"
        env         = true
        perms       = "400"
      }

      template {
        destination = "local/export-loop.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

while :; do
  # -c/-d keep the export incremental: unchanged documents are skipped and
  # documents deleted in paperless are removed from the export.
  python3 /usr/src/paperless/src/manage.py document_exporter /backup \
    --compare-checksums --delete --no-progress-bar

  curl -fsS -X POST --max-time 15 \
    -H "Authorization: Bearer $HEARTBEAT_TOKEN" \
    "http://observability.ts.dbyte.xyz:8080/api/v1/endpoints/backups_paperless/external?success=true" || true

  sleep 86400
done
EOH
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }

    task "paperless-broker" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image      = "docker.io/library/redis:7"
        force_pull = true
        ports      = ["redis"]
      }

      resources {
        cpu    = 100
        memory = 50
      }
    }
  }
}
