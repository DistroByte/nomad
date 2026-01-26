job "paperless-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 0 * * 0"]
    prohibit_overlap = true
  }

  group "db-backup" {
    task "paperless-backup" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data = <<EOH
#!/bin/bash

docker exec $(docker ps -aqf "name=^paperless-webserver-*") bash document_exporter ../export

file=$(du -sh /data/paperless/export/ | cut -f1 | xargs | sed 's/$//')

if test "$file"; then
  exit 0
else
  curl -H "Content-Type: application/json" -d '{"content": "`Paperless` backup has just **FAILED**\nFile size: `'"$file"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }}
fi
EOH

        destination = "local/script.sh"
      }
    }
  }
}
