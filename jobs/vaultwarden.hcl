job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "vaultwarden"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.vaultwarden.rule=Host(`vault.dbyte.xyz`)",
        "traefik.http.routers.vaultwarden.entrypoints=websecure",
        "traefik.http.routers.vaultwarden.tls.certresolver=lets-encrypt"
      ]
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image = "vaultwarden/server:latest"

        volumes = [
          "/data/vaultwarden/data:/data"
        ]
      }

      template {
        data = <<EOF
DOMAIN=https://vault.dbyte.xyz
DATABASE_URL=postgresql://{{ key "vault/db/user" }}:{{ key "vault/db/pass" }}@postgresql.service.consul/vaultwarden
SIGNUPS_ALLOWED=false
ADMIN_TOKEN={{ key "vault/admin/token" }}
YUBICO_CLIENT_ID={{ key "vault/yubico/client_id" }}
YUBICO_SECRET_KEY={{ key "vault/yubico/secret_key" }}
SMTP_HOST={{ key "mail/google/host" }}
SMTP_FROM=Vaultwarden <vaultwarden@dbyte.xyz>
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
        memory = 512
      }
    }
  }
}