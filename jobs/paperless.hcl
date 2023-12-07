job "paperless" {
  datacenters = ["dc1"]
  type        = "service"

  group "paperless-web" {
    network {
      port "http" {
        static = 8067
      }
      port "redis" {
        to = 6379
      }
    }

    service {
      name = "paperless"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.paperless.rule=Host(`paperless.dbyte.xyz`)",
        "traefik.http.routers.paperless.entrypoints=websecure",
        "traefik.http.routers.paperless.tls=true",
        "traefik.port=${NOMAD_PORT_http}",
        "traefik.http.routers.paperless.tls.certresolver=lets-encrypt",
        "traefik.http.middlewares.paperless.headers.contentSecurityPolicy=default-src 'self'; img-src 'self' data:"
      ]
    }

    task "paperless-webserver" {
      driver = "docker"

      env {
        PAPERLESS_REDIS  = "redis://${NOMAD_ADDR_redis}"
        PAPERLESS_DBHOST = "postgresql.service.consul"
        PAPERLESS_PORT   = "${NOMAD_PORT_http}"
      }

      config {
        image = "ghcr.io/paperless-ngx/paperless-ngx:latest"
        ports = ["http"]

        volumes = [
          "/data/paperless/consume:/usr/src/paperless/consume",
          "/data/paperless/data:/usr/src/paperless/data",
          "/data/paperless/media:/usr/src/paperless/media",
          "/data/paperless/export:/usr/src/paperless/export",
          "/data/paperless/preconsume:/usr/src/paperless/preconsume",
        ]
      }

      template {
        data = <<EOH
PAPERLESS_DBPASS={{ key "paperless/db/pass" }}
PAPERLESS_DBUSER={{ key "paperless/db/user" }}
PAPERLESS_SECRETKEY={{ key "paperless/env/secret" }}
PAPERLESS_URL={{ key "paperless/env/url" }}
PAPERLESS_ADMIN_USER={{ key "paperless/admin/user" }}
PAPERLESS_ADMIN_PASSWORD={{ key "paperless/admin/pass" }}
PAPERLESS_PRE_CONSUME_SCRIPT={{ key "paperless/env/preconsume-script" }}
PAPERLESS_ALLOWED_HOSTS="localhost,192.168.1.4,192.168.1.3,paperless.dbyte.xyz"
PAPERLESS_CONSUMER_POLLING=1
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
    }
  }
}
