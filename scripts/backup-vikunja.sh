#!/bin/bash

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

databasebak=/backups/vikunja/db/vikunja-$timestamp.sql
#attachments=/etc/docker-compose/vikunja/files/
#attachmentsbak=/etc/docker-compose/vikunja/backups/attach/vikunja-$timestamp.tar.gz
#
#tar -zcf $attachmentsbak $attachments

allocation_id=$(nomad job allocs -t '{{ range . }}{{ if eq .ClientStatus "running" }}{{ print .ID }}{{ end }}{{ end }}' vikunja)

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
