job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    volume "vaultwarden-data" {
      type            = "csi"
      read_only       = false
      source          = "vaultwarden"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vaultwarden.rule=Host(`vault.dbyte.xyz`)",
      ]
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:1.35.1"
        ports = ["http"]
      }

      volume_mount {
        volume      = "vaultwarden-data"
        destination = "/data"
        read_only   = false
      }

      template {
        data = <<EOF
DOMAIN=https://vault.dbyte.xyz
SIGNUPS_ALLOWED=false
ADMIN_TOKEN={{ key "vault/admin/token" }}
YUBICO_CLIENT_ID={{ key "vault/yubico/client-id" }}
YUBICO_SECRET_KEY={{ key "vault/yubico/secret" }}
SMTP_HOST={{ key "mail/google/host" }}
SMTP_FROM=vaultwarden@dbyte.xyz
SMTP_PORT=465
SMTP_SECURITY=force_tls
SMTP_USERNAME={{ key "mail/vaultwarden/username" }}
SMTP_PASSWORD={{ key "mail/vaultwarden/password" }}
EOF

        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 200
      }
    }
  }
}
