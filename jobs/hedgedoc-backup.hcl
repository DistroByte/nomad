job "hedgedoc-backup" {
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

file=/backups/hedgedoc/hedgedoc-$(date +%Y-%m-%d_%H-%M-%S).sql

docker exec $(docker ps -aqf "name=^hedgedoc-db-*") pg_dump hedgedoc -U hedgedoc > "${file}"

find /backups/hedgedoc/hedgedoc* -ctime +14 -exec rm {} \;

file_size=$(find $file -exec du -sh {} \; | cut -f1 | xargs | sed 's/$//')

if test -f "$file"; then
  exit 0
else
  curl -H "Content-Type: application/json" -d '{"content": "`HedgeDoc` backup has just **FAILED**\nFile name: `'"$file"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }} 
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
