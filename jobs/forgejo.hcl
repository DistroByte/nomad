job "forgejo" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "web" {
    network {
      port "http" {
        to = 3000
      }
      port "ssh" {
        static = 222
        to     = 22
      }
    }

    service {
      name = "forgejo"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.forgejo.rule=Host(`git.dbyte.xyz`)",
      ]
    }

    task "forgejo" {
      driver = "docker"

      config {
        image = "codeberg.org/forgejo/forgejo:10"
        ports = ["http"]

        volumes = [
          "/data/forgejo:/data",
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
GITEA__database__NAME = "forgejodb"
GITEA__database__USER = "{{ key "forgejo/db/user" }}"
GITEA__database__PASSWD = "{{ key "forgejo/db/pass" }}"

GITEA__metrics__ENABLED = "true"
EOF

        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 300
        memory = 500
      }
    }
  }
}
