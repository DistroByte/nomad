job "vikunja" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      mode = "bridge"
      port "http" {
        to     = 80
        static = 80
      }
      port "db" {
        to     = 3306
        static = 3306
      }
      port "api" {
        to     = 3456
        static = 3456
      }
    }

    service {
      name = "vikunja"
      port = "http"

      check {
        name     = "global_check"
        type     = "http"
        interval = "10s"
        timeout  = "2s"
        path     = "/"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vikunja-api.rule=Host(`todo.dbyte.xyz`)",
        "traefik.http.routers.vikunja-api.entrypoints=websecure",
        "traefik.http.routers.vikunja-api.tls.certResolver=lets-encrypt",
      ]
    }

    task "vikunja-api" {
      driver = "docker"

      template {
        data = <<EOH
VIKUNJA_DATABASE_HOST="{{ env "NOMAD_IP_db" }}"
VIKUNJA_DATABASE_PASSWORD="{{ key "vikunja/db/password" }}"
VIKUNJA_DATABASE_TYPE="mysql"
VIKUNJA_DATABASE_USER="{{ key "vikunja/db/username" }}"
VIKUNJA_DATABASE_DATABASE="{{ key "vikunja/db/database" }}"
VIKUNJA_SERVICE_JWTSECRET="{{ key "vikunja/jwtsecret" }}"
VIKUNJA_SERVICE_PUBLICURL="https://todo.dbyte.xyz/"
VIKUNJA_SERVICE_ENABLEEMAILREMINDERS=1
VIKUNJA_MAILER_ENABLED="true"
VIKUNJA_MAILER_FORCESSL=false
VIKUNJA_MAILER_AUTHTYPE=plain
VIKUNJA_MAILER_FROMEMAIL="vikunja@distrobyte.io"
VIKUNJA_MAILER_HOST="{{ key "mail/google/host" }}"
VIKUNJA_MAILER_PORT="{{ key "mail/google/port" }}"
VIKUNJA_MAILER_USERNAME="{{ key "mail/vikunja/username" }}"
VIKUNJA_MAILER_PASSWORD="{{ key "mail/vikunja/password" }}"
VIKUNJA_METRICS_ENABLED=true
EOH

        destination = "secrets/file.env"
        env         = true
      }

      config {
        image = "vikunja/vikunja"
        ports = ["api", "http"]
      }
    }

    task "vikunja-db" {
      driver = "docker"

      config {
        image = "mariadb:10"
        ports = ["db"]
      }

      template {
        data = <<EOH
MYSQL_ROOT_PASSWORD="{{ key "vikunja/db/rootpassword" }}"
MYSQL_USER="{{ key "vikunja/db/username" }}"
MYSQL_PASSWORD="{{ key "vikunja/db/password" }}"
MYSQL_DATABASE="{{ key "vikunja/db/database" }}"
EOH

        destination = "secrets/file.env"
        env         = true
      }
    }
  }
}
