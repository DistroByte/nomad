job "hedgedoc" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 3000
      }

      port "db" {
        to = 5432
      }
    }

    service {
      name = "hedgedoc"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.frontend.headers.STSSeconds=63072000",
        "traefik.frontend.headers.browserXSSFilter=true",
        "traefik.frontend.headers.contentTypeNosniff=true",
        "traefik.frontend.headers.customResponseHeaders=alt-svc:h2=l3sb47bzhpbelafss42pspxzqo3tipuk6bg7nnbacxdfbz7ao6semtyd.onion:443; ma=2592000",
        "traefik.enable=true",
        "traefik.port=${NOMAD_PORT_http}",
        "traefik.http.routers.md.rule=Host(`md.james-hackett.ie`)",
        "traefik.http.routers.md.tls=true",
        "traefik.http.routers.md.tls.certresolver=lets-encrypt",
        "alloc=${NOMAD_ALLOC_ID}"
      ]
    }

    task "app" {
      driver = "docker"

      env {
        CMD_IMAGE_UPLOAD_TYPE  = "imgur"
        CMD_IMGUR_CLIENTID     = "fe790a1b5b9f642"
        CMD_ALLOW_FREEURL      = "true"
        CMD_DEFAULT_PERMISSION = "private"
        CMD_DB_URL             = "postgres://hedgedoc:password@${NOMAD_ADDR_db}/hedgedoc"
        CMD_DOMAIN             = "md.james-hackett.ie"
        CMD_HSTS_PRELOAD       = "true"
        CMD_USE_CDN            = "true"
        CMD_PROTOCOL_USESSL    = "true"
        CMD_URL_ADDPORT        = "false"
      }

      config {
        image = "quay.io/hedgedoc/hedgedoc:1.9.9"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/hedgedoc/public/uploads"
          source   = "/data/hedgedoc/uploads"
          readonly = false
        }

      }
    }

    task "hedgedoc-db" {
      driver = "docker"

      env {
        POSTGRES_USER     = "hedgedoc"
        POSTGRES_PASSWORD = "password"
        POSTGRES_DB       = "hedgedoc"
      }

      config {
        image = "postgres:9.6"
        ports = ["db"]
      }
    }
  }
}

