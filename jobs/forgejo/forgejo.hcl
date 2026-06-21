job "forgejo" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
      port "ssh" {
        static = 222
        to     = 22
      }
    }

    volume "forgejo-db" {
      type            = "csi"
      read_only       = false
      source          = "forgejo-db"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
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
        image      = "codeberg.org/forgejo/forgejo:11"
        force_pull = true
        ports      = ["http", "ssh"]

        volumes = [
          "/data/forgejo:/data",
          "/etc/timezone:/etc/timezone:ro",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      volume_mount {
        volume      = "forgejo-db"
        destination = "/db"
        read_only   = false
      }

      template {
        data = <<EOF
USER_UID = "1000"
USER_GID = "1000"
GITEA__database__DB_TYPE = "sqlite3"
GITEA__database__PATH    = "/db/forgejo.db"

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
