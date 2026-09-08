job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

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

      check {
        type     = "http"
        path     = "/alive"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "vaultwarden" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image      = "vaultwarden/server:1.37.2"
        force_pull = true
        ports      = ["http"]
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
        cpu    = 150
        memory = 200
      }
    }

    # Companion rather than a separate periodic job: the CSI volume is
    # single-node-writer, so only a task in this group can reach the live data.
    task "backup" {
      driver = "docker"

      config {
        image      = "alpine:3.22"
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup-loop.sh"]
        # Host network like gatus-heartbeat: MagicDNS names only resolve from
        # the host network namespace.
        network_mode = "host"

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups/vaultwarden"
        }
      }

      # Not read_only: sqlite readers need to create/read the -wal and -shm
      # files next to the database.
      volume_mount {
        volume      = "vaultwarden-data"
        destination = "/data"
      }

      template {
        destination = "secrets/heartbeat.env"
        env         = true
        perms       = "400"
        data        = <<EOH
HEARTBEAT_TOKEN={{ key "gatus/heartbeat-token" }}
EOH
      }

      template {
        destination = "local/backup-loop.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu
apk add --no-cache sqlite curl >/dev/null

while :; do
  stamp=$(date +%Y%m%d%H%M)

  # .backup is the online-safe copy; never plain-copy a live sqlite file.
  sqlite3 /data/db.sqlite3 ".backup /backup/db.$stamp.sqlite3"

  extras=""
  for f in attachments sends config.json rsa_key.pem rsa_key.pub.pem; do
    [ -e "/data/$f" ] && extras="$extras $f"
  done
  # shellcheck disable=SC2086
  tar czf "/backup/files.$stamp.tar.gz" -C /data $extras

  ls -1t /backup/db.*.sqlite3 2>/dev/null | tail -n +8 | while read -r old; do rm -f "$old"; done
  ls -1t /backup/files.*.tar.gz 2>/dev/null | tail -n +8 | while read -r old; do rm -f "$old"; done

  curl -fsS -X POST --max-time 15 \
    -H "Authorization: Bearer $HEARTBEAT_TOKEN" \
    "http://observability.ts.dbyte.xyz:8080/api/v1/endpoints/backups_vaultwarden/external?success=true" || true

  sleep 86400
done
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
