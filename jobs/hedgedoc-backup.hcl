job "hedgedoc-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */3 * * * *"]
    prohibit_overlap = true
  }

  group "db-backup" {
    task "hedgedoc-backup" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data = <<EOH
#!/bin/bash

file=/backups/hedgedoc/hedgedoc-$(date +%Y-%m-%d_%H-%M-%S).sql

alloc_id=$(curl -s --request GET http://nomad.service.consul:4646/v1/job/hedgedoc/allocations | jq '.[0].ID' | tr -d '"')

nomad alloc exec --task hedgedoc-db $alloc_id pg_dump hedgedoc -U hedgedoc > ${file}

find /backups/hedgedoc/hedgedoc* -ctime +14 -exec rm {} \;

file_size=$(find $file -exec du -sh {} \; | cut -f1 | xargs | sed 's/$//')

if [ -s "$file" ]; then
  exit 0
else
  rm $file
  curl -H "Content-Type: application/json" -d '{"content": "`HedgeDoc` backup has just **FAILED**\nFile name: `'"$file"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }} 
fi
EOH

        destination = "local/script.sh"
      }
    }
  }
}
