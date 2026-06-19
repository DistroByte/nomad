job "immich-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 3 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "pg-dump" {
      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup.sh"]
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -e
{{ range service "immich-postgres" -}}
pg_dumpall -h {{ .Address }} -p {{ .Port }} -U "{{ key "immich/db/user" }}" | \
  gzip --rsyncable > /backup/backup.$(date +"%Y%m%d%H%M").sql.gz
echo "Cleaning up backups older than 7 days..."
find /backup -maxdepth 1 -type f -name '*.sql.gz' -printf '%T@ %p\n' | \
  sort -nr | tail -n +8 | cut -d' ' -f2- | xargs -r rm --
{{ else -}}
echo "ERROR: immich-postgres service not found in Consul" >&2
exit 1
{{- end }}
EOH
      }

      template {
        destination = "secrets/pg.env"
        env         = true
        perms       = "400"
        data        = <<EOH
PGPASSWORD = {{ key "immich/db/password" }}
EOH
      }

      volume_mount {
        volume      = "immich-postgres-backup"
        destination = "/backup"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    volume "immich-postgres-backup" {
      type            = "csi"
      source          = "immich-postgres-backup"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
  }
}
