job "forgejo" {
  datacenters = ["dc1"]
  type = "service"

  group "forgejo" {
    count = 1

    network {
      port "http" {
        to = 3000
      }

      port "ssh" {
        static = 2222
        to     = 22
      }
    }

    volume "forgejo" {
      type            = "csi"
      source          = "forgejo"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    restart {
      attempts = 5
      delay    = "30s"
    }

    task "app" {
      driver = "docker"

      config {
        image = "codeberg.org/forgejo/forgejo:13"
        ports = ["ssh", "http"]
      }

      env {
        ROOT_URL = "https://git.dbyte.xyz/"
      }

      volume_mount {
        volume      = "forgejo"
        destination = "/data"
        read_only   = false
      }

      resources {
        cpu    = 200
        memory = 512
      }

      service {
        name = "forgejo"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.forgejo.rule=Host(`git.dbyte.xyz`)",
        ]
      }
    }
  }
}