job "pihole-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  # The Pi-holes run as Docker Compose stacks on hermes and zeus rather than as
  # Nomad jobs, so this pulls a Teleporter export from each over its HTTP API
  # and drops both on the /backups NFS share.
  #
  # Teleporter is the only backup that matters here: everything else about these
  # resolvers is config-as-code in ansible/group_vars/pihole.yaml. What the
  # export carries that the repo does not is the allow/deny/group/client rules.
  periodic {
    crons            = ["0 4 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "export" {
      driver = "docker"

      config {
        image      = "alpine:latest"
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup.sh"]

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups/pihole"
        }
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOH
PIHOLE_PASSWORD={{ key "pihole/password" }}
EOH
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

apk add --no-cache curl jq >/dev/null

stamp=$(date +%Y%m%d%H%M)
failed=0

# By IP, not name: this job must keep working when the thing it is backing up
# is the thing that resolves names.
for node in hermes:192.168.0.4 zeus:192.168.0.3; do
  name=$${node%%:*}
  addr=$${node#*:}
  base="http://$addr:8053"
  out="/backup/pihole-$name-teleporter.$stamp.zip"

  sid=$(curl -fsS --connect-timeout 5 -X POST "$base/api/auth" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg p "$PIHOLE_PASSWORD" '{password: $p}')" \
    | jq -r '.session.sid // empty') || { echo "$name: auth failed" >&2; failed=1; continue; }

  if ! curl -fsS -o "$out" -H "X-FTL-SID: $sid" "$base/api/teleporter"; then
    echo "$name: teleporter export failed" >&2
    rm -f "$out"
    failed=1
  elif [ ! -s "$out" ]; then
    echo "$name: teleporter export was empty" >&2
    rm -f "$out"
    failed=1
  fi

  curl -fsS -X DELETE -H "X-FTL-SID: $sid" "$base/api/auth" >/dev/null || true

  # Keep the 14 most recent exports per node.
  ls -1t "/backup/pihole-$name-teleporter."*.zip 2>/dev/null | tail -n +15 | while read -r old; do
    rm -f "$old"
  done
done

# One resolver's export is better than none, but a partial run must not look
# like a clean one — the pair exists so that neither is allowed to rot quietly.
exit "$failed"
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
