job "vikunja-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */3 * * * *"]
    prohibit_overlap = true
  }

  group "db-backup" {
    task "vikunja-backup" {
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

allocation_id=$(curl -s --request GET http://nomad.service.consul:4646/v1/job/vikunja/allocations | jq '.[0].ID' | tr -d '"')

nomad alloc exec --task vikunja-db $allocation_id mysqldump -u vikunja -p$(consul kv get vikunja/db/password) vikunja > ${databasebak}

find /backups/vikunja/db/vikunja-* -ctime +14 -exec rm {} \;

# when attachments come back
#-a -f "$attachmentsbak"
if [ -s "$databasebak" ]; then
  exit 0
else
  curl -H "Content-Type: application/json" -d '{"content": "`Vikunja` backup has just **FAILED**\nFile name: `'"$databasebak"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }}
  rm $databasebak
fi
EOH

        destination = "local/script.sh"
      }

    }
  }
}
