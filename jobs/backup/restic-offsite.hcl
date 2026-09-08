job "restic-offsite" {
  datacenters = ["dc1"]
  type        = "batch"

  # 05:00: after immich (03:00), photo/pihole (04:00) and the vaultwarden and
  # paperless companion tasks have produced the night's dumps.
  periodic {
    crons            = ["0 5 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    restart {
      attempts = 1
    }

    # The nightly DB dumps live on two different dionysus exports: /backups
    # (host NFS mount) and these two CSI volumes under /volume1/data.
    volume "immich-postgres-backup" {
      type            = "csi"
      source          = "immich-postgres-backup"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
      read_only       = true
    }

    volume "photo-mysql-backup" {
      type            = "csi"
      source          = "photo-mysql-backup"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
      read_only       = true
    }

    task "restic" {
      driver = "docker"

      config {
        image      = "restic/restic:0.19.1"
        entrypoint = ["/bin/sh"]
        args       = ["/local/offsite.sh"]
        # Host network like gatus-heartbeat: MagicDNS names only resolve from
        # the host network namespace.
        network_mode = "host"

        mount {
          type     = "bind"
          target   = "/data/backups"
          source   = "/backups"
          readonly = true
        }
      }

      volume_mount {
        volume      = "immich-postgres-backup"
        destination = "/data/immich-postgres-backup"
        read_only   = true
      }

      volume_mount {
        volume      = "photo-mysql-backup"
        destination = "/data/photo-mysql-backup"
        read_only   = true
      }

      # Offsite target is Backblaze B2 via its S3-compatible endpoint, kept
      # failure-independent of the Oracle account that hosts the tailnet
      # control plane, relay and third server. RESTIC_REPOSITORY looks like
      # s3:https://s3.<region>.backblazeb2.com/<bucket>/homelab
      template {
        destination = "secrets/restic.env"
        env         = true
        perms       = "400"
        data        = <<EOH
RESTIC_REPOSITORY={{ key "restic/repository" }}
RESTIC_PASSWORD={{ key "restic/password" }}
AWS_ACCESS_KEY_ID={{ key "restic/b2-key-id" }}
AWS_SECRET_ACCESS_KEY={{ key "restic/b2-application-key" }}
HEARTBEAT_TOKEN={{ key "gatus/heartbeat-token" }}
EOH
      }

      template {
        destination = "local/offsite.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

restic cat config >/dev/null 2>&1 || restic init

restic backup /data --host homelab

# Prune only on Sundays to keep the nightly run cheap; verify a sample of
# repository data on the first of the month.
if [ "$(date +%u)" = "7" ]; then
  restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 6 --prune
else
  restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 6
fi
if [ "$(date +%d)" = "01" ]; then
  restic check --read-data-subset=5%
fi

# busybox wget: --post-data makes it a POST
wget -q -O /dev/null -T 15 --post-data="" \
  --header="Authorization: Bearer $HEARTBEAT_TOKEN" \
  "http://observability.ts.dbyte.xyz:8080/api/v1/endpoints/backups_offsite/external?success=true" || true
EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
