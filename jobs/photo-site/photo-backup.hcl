job "photo-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 4 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "mysql-dump" {
      driver = "docker"

      config {
        image      = "mysql:8.0"
        force_pull = true
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup.sh"]
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -e
{{ range service "photo-mysql" -}}
MYSQL_PWD="$MYSQL_PASSWORD" mysqldump \
  -h {{ .Address }} \
  -P {{ .Port }} \
  -u "$MYSQL_USER" \
  --single-transaction \
  --no-tablespaces \
  --routines \
  --triggers \
  "$MYSQL_DATABASE" | \
  gzip --rsyncable > /backup/backup.$(date +"%Y%m%d%H%M").sql.gz
echo "Cleaning up backups older than 7 days..."
find /backup -maxdepth 1 -type f -name '*.sql.gz' -printf '%T@ %p\n' | \
  sort -nr | tail -n +8 | cut -d' ' -f2- | xargs -r rm --
{{ else -}}
echo "ERROR: photo-mysql service not found in Consul" >&2
exit 1
{{- end }}
EOH
      }

      template {
        destination = "secrets/mysql.env"
        env         = true
        perms       = "400"
        data        = <<EOH
MYSQL_USER     = {{ key "ghost/db/user" }}
MYSQL_PASSWORD = {{ key "ghost/db/password" }}
MYSQL_DATABASE = {{ key "ghost/db/database" }}
EOH
      }

      volume_mount {
        volume      = "photo-mysql-backup"
        destination = "/backup"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    volume "photo-mysql-backup" {
      type            = "csi"
      source          = "photo-mysql-backup"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
  }
}
