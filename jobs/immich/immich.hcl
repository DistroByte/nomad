job "immich" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  group "api-server" {
    network {
      port "api" {
        to = 2283
      }
    }

    service {
      name = "immich"

      task = "server"
      port = "api"

      check {
        type     = "http"
        path     = "/api/server/ping"
        interval = "5s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.immich.rule=Host(`immich.dbyte.xyz`)",
      ]
    }

    # The main immich API server
    task "server" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image = "ghcr.io/immich-app/immich-server:release"
        force_pull = true
        ports = ["api"]
      }

      env {
        NODE_ENV = "production"
        IMMICH_MEDIA_LOCATION = "/data"
        TZ = "Europe/Dublin"

        # user and group ID
        PUID = 1026
        PGID = 100

        IMMICH_TELEMETRY_INCLUDE = "all"

        IMMICH_WORKERS_INCLUDE = "api"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = "400"
        data        = <<EOH
{{- range service "immich-postgres" }}
DB_URL=postgres://{{ key "immich/db/user" }}:{{ key "immich/db/password" }}@{{ .Address }}:{{ .Port }}/immich
{{- end }}
{{- range service "immich-valkey" }}
REDIS_HOSTNAME={{ .Address }}
REDIS_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        memory = 900
        cpu    = 512
      }

      volume_mount {
        volume      = "immich-data"
        destination = "/data"
      }
      volume_mount {
        volume      = "immich-homes"
        destination = "/homes"
      }
    }

    volume "immich-data" {
      type            = "csi"
      source          = "immich-data"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
    volume "immich-homes" { # external library location
      type            = "csi"
      source          = "immich-homes"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
  }

  // --- Immich Worker ---
  group "worker" {
    count = 2
    constraint {
      distinct_hosts = true
    }

    network {
      port "worker" {
        to = 2283
      }
    }

    service {
      name = "immich-worker"
      port = "worker"

      check {
        type     = "http"
        path     = "/api/server/ping"
        interval = "5s"
        timeout  = "2s"
      }
    }

    # task worker, doing all the processing async
    task "server" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image = "ghcr.io/immich-app/immich-server:release"
        force_pull = true

        ports = ["worker"]

        devices = [ # map Intel QuickSync to container, allowing for hardware encoding
          {
            host_path = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]
      }

      env {
        NODE_ENV = "production"
        IMMICH_MEDIA_LOCATION = "/data"

        # user and group ID
        PUID = 1026
        PGID = 100

        TZ = "Europe/Dublin"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = "400"
        data        = <<EOH
{{- range service "immich-postgres" }}
DB_URL=postgres://{{ key "immich/db/user" }}:{{ key "immich/db/password" }}@{{ .Address }}:{{ .Port }}/immich
{{- end }}
{{- range service "immich-valkey" }}
REDIS_HOSTNAME={{ .Address }}
REDIS_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        memory = 3500
        cpu    = 1600
      }

      volume_mount {
        volume      = "immich-data"
        destination = "/data"
      }
      volume_mount {
        volume      = "immich-homes"
        destination = "/homes"
      }
    }

    volume "immich-data" {
      type            = "csi"
      source          = "immich-data"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
    volume "immich-homes" { # external library location
      type            = "csi"
      source          = "immich-homes"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
  }

  // --- Immich Machine Learning ---
  group "machine-learning" {
    count = 1
    constraint {
      distinct_hosts = true
    }

    network {
      port "ml" {
        static = 13030
      }
    }

    ephemeral_disk { # Used to cache the machine learning model
      size    = 3000 # MB
      migrate = true
    }

    service {
      name = "immich-ml"
      port = "ml"

      check {
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image = "ghcr.io/immich-app/immich-machine-learning:release"
        force_pull = true
        ports = ["ml"]
      }

      env {
        TMPDIR       = "/tmp"
        MPLCONFIGDIR = "/local/mplconfig"
        IMMICH_PORT  = "13030"

        TZ           = "Europe/Dublin"

        MACHINE_LEARNING_CACHE_FOLDER    = "${NOMAD_ALLOC_DIR}/data/cache"
        MACHINE_LEARNING_MODEL_TTL       = 0 # don't unload the model cache, re-fetching slows down queries a lot
        MACHINE_LEARNING_REQUEST_THREADS = 4
        # add your models from Settings -> Machine Learning here
        MACHINE_LEARNING_PRELOAD__CLIP   = "ViT-B-16-SigLIP-256__webli"
        MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION = "buffalo_l"
      }

      resources {
        memory = 3172
        cpu    = 1500
      }
    }
  }

  // --- Immich Postgres database and Valkey instance ---
  group "backend" {
    // Primary postgres on hermes; replica group pins to zeus
    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "hermes"
    }

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    network {
      port "postgres" {
        static = 5432
        to     = 5432
      }

      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "immich-postgres"

      task = "postgres"
      port = "postgres"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "psql -U $POSTGRES_USER -d immich  -c 'SELECT 1' || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    # Immich is using Valkey to communicate with the worker microservices
    service {
      name = "immich-valkey"

      task = "valkey"
      port = "valkey"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "redis-cli ping || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "postgres" {
      driver = "docker"
      shutdown_delay = "5s"
      kill_timeout   = "30s"

      # backs up the Postgres database and removes all files in the backup folder which are older than 3 days.
      action "backup-postgres" {
        command = "/bin/sh"
        args    = ["-c", <<EOF
pg_dumpall -U "$POSTGRES_USER" | gzip --rsyncable > /backup/backup.$(date +"%Y%m%d%H%M").sql.gz
echo "cleaning up backup files older than 7 days ..."
find /backup -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | tail -n +7 | cut -d' ' -f2- | xargs -r rm --
EOF
        ]
      }

      config {
        image      = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"
        force_pull = true
        ports      = ["postgres"]
        args = [
          "-c", "shared_preload_libraries=vchord.so",
          "-c", "wal_level=replica",
          "-c", "max_wal_senders=5",
          "-c", "wal_keep_size=128",
          "-c", "hot_standby=on",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = "400"
        data        = <<EOH
POSTGRES_PASSWORD    = {{ key "immich/db/password" }}
POSTGRES_USER        = {{ key "immich/db/user" }}
DB_URL               = postgres://{{ key "immich/db/user" }}:{{ key "immich/db/password" }}@127.0.0.1:5432/immich
POSTGRES_INITDB_ARGS = '--data-checksums'
EOH
      }

      volume_mount {
        volume      = "immich-postgres"
        destination = "/var/lib/postgresql/data"
      }

      volume_mount {
        volume      = "immich-postgres-backup"
        destination = "/backup"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }

    # Idempotently creates the replication role and pg_hba.conf entry on every
    # start so replication is ready without manual intervention after restore.
    task "setup-replication" {
      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"
        entrypoint = ["/bin/sh"]
        args       = ["/local/setup.sh"]
      }

      template {
        destination = "secrets/env"
        env         = true
        perms       = "400"
        data        = <<EOH
PGPASSWORD={{ key "immich/db/password" }}
EOH
      }

      template {
        destination = "local/setup.sql"
        data        = <<EOH
DO $body$BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '{{ key "immich/db/replicator_password" }}';
  END IF;
END$body$;
EOH
      }

      template {
        destination = "local/setup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -e
until pg_isready -h hermes.internal -p 5432; do sleep 2; done
psql -h hermes.internal -U "{{ key "immich/db/user" }}" -d postgres -f /local/setup.sql
grep -q 'replication.*replicator' /var/lib/postgresql/data/pg_hba.conf || \
  printf '\nhost replication replicator 0.0.0.0/0 scram-sha-256\n' \
    >> /var/lib/postgresql/data/pg_hba.conf
psql -h hermes.internal -U "{{ key "immich/db/user" }}" -d postgres -c 'SELECT pg_reload_conf()'
EOH
      }

      volume_mount {
        volume      = "immich-postgres"
        destination = "/var/lib/postgresql/data"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    # Valkey cache, used as an event queue to schedule jobs
    task "valkey" {
      driver = "docker"
      shutdown_delay = "5s"
      kill_timeout   = "10s"

      config {
        image = "valkey/valkey:9"
        force_pull = true
        ports = ["valkey"]

        args = [ "/local/valkey.conf" ]
      }

      template {
        destination = "local/valkey.conf"
        data        = <<EOH
# save every 60 seconds if at least 100 keys have changed
save 60 100

dir {{ env "NOMAD_ALLOC_DIR" }}/data
EOH
      }

      resources {
        memory = 200
        cpu    = 300
      }
    }

    volume "immich-postgres" {
      type      = "host"
      source    = "immich-postgres"
      read_only = false
    }

    volume "immich-postgres-backup" {
      type            = "csi"
      source          = "immich-postgres-backup"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }
  }

  // --- Immich Postgres replica (zeus) ---
  group "backend-replica" {
    // Replica on zeus local SSD; promote manually if hermes is lost (see docs/Immich.md)
    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "zeus"
    }

    network {
      port "postgres" {
        static = 5432
        to     = 5432
      }
    }

    service {
      name = "immich-postgres-replica"
      task = "postgres"
      port = "postgres"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "psql -U $POSTGRES_USER -d immich -c 'SELECT 1' || exit 1"]
        interval = "10s"
        timeout  = "5s"
      }
    }

    # Seeds the replica from the primary on first run via pg_basebackup.
    # On subsequent starts it refreshes primary_conninfo so replication
    # survives primary restarts on a different port.
    task "replica-init" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"
        entrypoint = ["/bin/sh"]
        args       = ["/local/init-replica.sh"]
      }

      template {
        destination = "local/init-replica.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -e
DATA_DIR=/var/lib/postgresql/data

if [ ! -f "$DATA_DIR/standby.signal" ]; then
  echo "Seeding replica from hermes.internal:5432..."
  until pg_isready -h hermes.internal -p 5432; do
    echo "Waiting for primary..."
    sleep 3
  done
  pg_basebackup \
    -h hermes.internal \
    -p 5432 \
    -U replicator \
    --pgdata="$DATA_DIR" \
    --wal-method=stream \
    --progress \
    --checkpoint=fast
  touch "$DATA_DIR/standby.signal"
fi

# Refresh primary_conninfo on every start so replication survives restarts
sed -i '/^primary_conninfo/d' "$DATA_DIR/postgresql.auto.conf" 2>/dev/null || true
printf "primary_conninfo = 'host=hermes.internal port=5432 user=replicator password=%s sslmode=prefer'\n" \
  "$PGPASSWORD" >> "$DATA_DIR/postgresql.auto.conf"
EOH
      }

      template {
        destination = "secrets/replica.env"
        env         = true
        perms       = "400"
        data        = <<EOH
PGPASSWORD = {{ key "immich/db/replicator_password" }}
EOH
      }

      volume_mount {
        volume      = "immich-postgres-replica"
        destination = "/var/lib/postgresql/data"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "postgres" {
      driver = "docker"
      shutdown_delay = "5s"
      kill_timeout   = "30s"

      config {
        image      = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"
        force_pull = true
        ports      = ["postgres"]
        args = [
          "-c", "shared_preload_libraries=vchord.so",
          "-c", "hot_standby=on",
        ]
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = "400"
        data        = <<EOH
POSTGRES_USER     = {{ key "immich/db/user" }}
POSTGRES_PASSWORD = {{ key "immich/db/password" }}
EOH
      }

      volume_mount {
        volume      = "immich-postgres-replica"
        destination = "/var/lib/postgresql/data"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    volume "immich-postgres-replica" {
      type      = "host"
      source    = "immich-postgres-replica"
      read_only = false
    }
  }
}
