job "vikunja" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 80
      }
      port "db" {
        static = 3306
      }
      port "api" {
        to = 3456
      }
    }

    service {
      name = "vikunja"
      port = "http"

      check {
        name = "global_check"
	type = "http"
	interval = "10s"
	timeout = "2s"
	path = "/"
      }
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
VIKUNJA_SERVICE_FRONTENDURL="https://todo.dbyte.xyz/"
VIKUNJA_MAILER_ENABLED="true"
VIKUNJA_MAILER_HOST="{{ key "mail/distrobyte/host" }}"
VIKUNJA_MAILER_PORT="{{ key "mail/distrobyte/port" }}"
VIKUNJA_MAILER_USERNAME="{{ key "mail/vikunja/username" }}"
VIKUNJA_MAILER_PASSWORD="{{ key "mail/vikunja/password" }}"
EOH

        destination = "secrets/file.env"
	env = true
      }

      service {
        port = "api"
	name = "vikunja-api"

	tags = [
          "traefik.enable=true",
          "traefik.http.routers.vikunja-api.rule=Host(`todo.dbyte.xyz`) && PathPrefix(`/api/v1`, `/dav/`, `/.well-known/`)",
          "traefik.http.routers.vikunja-api.entrypoints=websecure",
          "traefik.http.routers.vikunja-api.tls.certResolver=lets-encrypt",
	]
      }

      config {
        image = "vikunja/api"
	ports = ["api"]
      }
    }

    task "vikunja-frontend" {
      driver = "docker"

      service {
        port = "http"
	name = "vikunja-frontend"
      
        check {
          name = "vikunja-frontend-check"
          type = "http"
          interval = "10s"
          timeout = "2s"
	  path = "/"
        }

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.vikunja-frontend.rule=Host(`todo.dbyte.xyz`)",
          "traefik.http.routers.vikunja-frontend.entrypoints=websecure",
          "traefik.http.routers.vikunja-frontend.tls=true",
          "traefik.http.routers.vikunja-frontend.tls.certresolver=lets-encrypt"
        ]
      }

      env {
        VIKUNJA_API_URL = "https://todo.dbyte.xyz/api/v1"
      }

      config {
        image = "vikunja/frontend"
	ports = ["http"]
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
	env = true
      }
    }
  }
}
