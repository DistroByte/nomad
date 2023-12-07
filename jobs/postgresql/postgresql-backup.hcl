job "postgresql-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */3 * * * *"]
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

file=/backups/postgresql/postgresql-$(date +%Y-%m-%d_%H-%M-%S).sql

alloc_id=$(curl -s --request GET http://nomad.service.consul:4646/v1/job/postgres/allocations | jq '.[0].ID' | tr -d '"')

nomad alloc exec $alloc_id pg_dumpall -U root > "${file}"

find /backups/postgresql/postgresql* -ctime +14 -exec rm {} \;

file_size=$(find $file -exec du -sh {} \; | cut -f1 | xargs | sed 's/$//')

if [ -s "$file" ]; then
  exit 0
else
  rm $file
  curl -H "Content-Type: application/json" -d '{"content": "`PostgreSQL` backup has just **FAILED**\nFile name: `'"$file"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }} 
fi
EOH

        destination = "local/script.sh"
      }

      template {
        data = <<EOH
#hostname:port:database:username:password
*:*:*:root:rootpassword
EOH

        destination = "local/.pgpass"
      }
    }
  }
}
