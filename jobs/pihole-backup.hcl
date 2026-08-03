job "pihole-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  # Pi-hole runs on dionysus (Synology) outside Nomad, so this pulls a Teleporter
  # export via its HTTP API and drops it on the /backups NFS share.
  periodic {
    crons            = ["0 4 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "export" {
      driver = "docker"

      config {
        image      = "alpine:latest"
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup.sh"]

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups/pihole"
        }
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

stamp=$(date +%Y%m%d%H%M)
out="/backup/pihole-teleporter.$stamp.zip"

# Pi-hole v6 Teleporter export. The API has no password set, so no auth is needed
# (busybox wget, IP to avoid container DNS on dionysus.internal).
wget -q -O "$out" "http://192.168.0.5/api/teleporter"
[ -s "$out" ] || { echo "teleporter export was empty" >&2; rm -f "$out"; exit 1; }

# Keep the 14 most recent exports.
ls -1t /backup/pihole-teleporter.*.zip 2>/dev/null | tail -n +15 | while read -r old; do
  rm -f "$old"
done
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
