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

      env {
        VIKUNJA_DATABASE_HOST = "${NOMAD_IP_db}"
        VIKUNJA_DATABASE_PASSWORD = "supersecret"
        VIKUNJA_DATABASE_TYPE = "mysql"
        VIKUNJA_DATABASE_USER = "vikunja"
        VIKUNJA_DATABASE_DATABASE = "vikunja"
        VIKUNJA_SERVICE_JWTSECRET = "abwdajdbakwjdbajdbkwajbdsmakmdlwka"
        VIKUNJA_SERVICE_FRONTENDURL = "https://todo.dbyte.xyz/"
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

      env {
	MYSQL_ROOT_PASSWORD = "supersupersecret"
        MYSQL_USER = "vikunja"
        MYSQL_PASSWORD = "supersecret"
        MYSQL_DATABASE = "vikunja"
      }

      config {
        image = "mariadb:10"
        ports = ["db"]
      }
    }
  }
}
