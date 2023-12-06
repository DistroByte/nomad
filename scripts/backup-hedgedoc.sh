#!/bin/bash

file=/backups/hedgedoc/hedgedoc-$(date +%Y-%m-%d_%H-%M-%S).sql

alloc_id=$(nomad job allocs -t '{{ range . }}{{ if eq .ClientStatus "running" }}{{ print .ID }}{{ end }}{{ end }}' hedgedoc)

nomad alloc exec --task hedgedoc-db $alloc_id pg_dump hedgedoc -U hedgedoc > ${file}

find /backups/hedgedoc/hedgedoc* -ctime +14 -exec rm {} \;

file_size=$(find $file -exec du -sh {} \; | cut -f1 | xargs | sed 's/$//')

if [ -s "$file" ]; then
  exit 0
else
  rm $file
  curl -H "Content-Type: application/json" -d '{"content": "`HedgeDoc` backup has just **FAILED**\nFile name: `'"$file"'`\nDate: `'"$(TZ=Europe/Dublin date)"'`"}' {{ key "discord/log/webhook" }}
fi
