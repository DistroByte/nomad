job "gitea" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 3000
      }
      port "ssh" {
	static = 2222
	to = 22
      }
    }

    service {
      name = "gitea"
      port = "http"

      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.gitea.rule=Host(`git.dbyte.xyz`)",
	"traefik.http.routers.gitea.entrypoints=websecure",
	"traefik.http.routers.gitea.tls.certresolver=lets-encrypt"
      ]
    }

    task "gitea" {
      driver = "docker"

      config {
        image = "gitea/gitea"
	ports = ["http"]

	volumes = [
	  "/data/gitea:/data",
	  "/etc/timezone:/etc/timezone:ro",
	  "/etc/localtime:/etc/localtime:ro"
	]
      }

      template {
	data = <<EOF
USER_UID = "1000"
USER_GID = "1000"
GITEA__database__DB_TYPE = "postgres"
GITEA__database__HOST = "postgresql.service.consul"
GITEA__database__NAME = "giteadb"
GITEA__database__USER = "{{ key "gitea/db/user" }}"
GITEA__database__PASSWD = "{{ key "gitea/db/pass" }}"

GITEA__metrics__ENABLED = "true"
EOF
	destination = "local/env"
	env = true
      }

      resources {
	cpu = 300
	memory = 500
      }
    }
  }
}
