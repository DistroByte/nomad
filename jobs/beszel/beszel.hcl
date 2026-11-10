job "beszel" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  group "hub" {
    count = 1

    network {
      port "http" {
        to = 8090
      }
    }

    volume "beszel-data" {
      type            = "csi"
      read_only       = false
      source          = "beszel"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "beszel"
      port = "http"

      check {
        type     = "http"
        path     = "/api/health"
        interval = "15s"
        timeout  = "3s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.beszel.rule=Host(`beszel.dbyte.xyz`)",
        "traefik.http.routers.beszel.middlewares=internal-only@file",
      ]
    }

    # The hub dials each agent on :45876 (ansible/playbooks/beszel-agent.yaml):
    # LAN addresses for the home nodes, tailnet addresses for the Oracle VMs.
    task "hub" {
      driver = "docker"

      config {
        image = "henrygd/beszel:0.21.1"
        ports = ["http"]
      }

      volume_mount {
        volume      = "beszel-data"
        destination = "/beszel_data"
        read_only   = false
      }

      # USER_EMAIL/USER_PASSWORD only take effect on first start, when they
      # create the admin account; later changes are made in the UI.
      template {
        data        = <<EOH
APP_URL=https://beszel.dbyte.xyz
USER_EMAIL={{ key "beszel/admin/email" }}
USER_PASSWORD={{ key "beszel/admin/password" }}
EOH
        destination = "secrets/hub.env"
        env         = true
        perms       = "400"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
