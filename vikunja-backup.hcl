job "vikunja-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    cron             = "0 */3 * * * *"
    prohibit_overlap = true
  }

  group "db-backup" {  
    task "postgres-backup" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data = <<EOH
#!/bin/bash

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

databasebak=/backups/vikunja/db/vikunja-$timestamp.sql
#attachments=/etc/docker-compose/vikunja/files/
#attachmentsbak=/etc/docker-compose/vikunja/backups/attach/vikunja-$timestamp.tar.gz
#
#tar -zcf $attachmentsbak $attachments
container=$(docker ps -aqf "name=^vikunja-db-*")
docker exec $container mysqldump -u vikunja -p"$(consul kv get vikunja/db/password)" vikunja > ${databasebak}

find /backups/vikunja/db/vikunja-* -ctime +14 -exec rm {} \;

# when attachments come back
#-a -f "$attachmentsbak"
if [ -f "$databasebak" ]; then
  exit 0
else
  curl -H "Content-Type: application/json" -d '{"content": "`Vikunja` backup has just **FAILED**\nFile name: `'"$databasebak"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }}
fi
EOH

        destination = "local/script.sh"
      }

      template {
        data = <<EOH
# as service 'db-task' is registered in Consul
# we wat to grab its 'alloc' tag
{{- range $tag, $services := service "db-task" | byTag -}}
{{if $tag | contains "alloc"}}
{{$allocId := index ($tag | split "=") 1}}
DB_ALLOC_ID="{{ $allocId }}"
{{end}}
{{end}}
        EOH
        destination = "secrets/file.env"
        env         = true
      }
    }
  }
}
