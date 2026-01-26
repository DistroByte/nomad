job "immich" {
  datacenters = ["dc1"]
  type        = "service"

  group "api-server" {
    network {
      port "api" {
        to = 2283
      }
    }

    service {
      name = "immich-api"

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

      config {
        image = "ghcr.io/immich-app/immich-server:release"
        force_pull = true
      }

      env {
        NODE_ENV              = "production"
        REDIS_HOSTNAME        = "immich-valkey"
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
        perms       = 400
        data        = <<EOH
DB_URL=postgres://{{- .db_user }}:{{- .db_pass }}@immich-postgres:${NOMAD_PORT_immich-postgres}/immich
EOH
      }

      resources {
        memory = 800
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
      access_mode     = "multi-node-reader-only"
      attachment_mode = "file-system"
      read_only       = true
    }
  }

  // --- Immich Worker ---
  group "worker" {
    count = "2"
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

      config {
        image = "ghcr.io/immich-app/immich-server:release"
        force_pull = true

        devices = [ # map Intel QuickSync to container, allowing for hardware encoding
          {
            host_path = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]
      }

      env {
        NODE_ENV              = "production"
        REDIS_HOSTNAME        = "127.0.0.1"
        IMMICH_MEDIA_LOCATION = "/data"

        # user and group ID
        PUID = 1026
        PGID = 100

        TZ = "Europe/Dublin"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = 400
        data        = <<EOH
{{- with nomadVar "nomad/jobs/immich" }}
DB_URL=postgres://{{- .db_user }}:{{- .db_pass }}@127.0.0.1:5432/immich
{{- end }}
EOH
      }

      resources {
        memory = 3500
        cpu    = 4000
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
      access_mode     = "multi-node-reader-only"
      attachment_mode = "file-system"
      read_only       = true
    }
  }

  // --- Immich Machine Learning ---
  group "machine-learning" {
    count = "2"
    constraint {
      distinct_hosts = true
    }

    network {
      port "ml" {
        to = 3003
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

      config {
        image = "ghcr.io/immich-app/immich-machine-learning:release"
        force_pull = true
      }

      env {
        TMPDIR       = "/tmp"
        MPLCONFIGDIR = "/local/mplconfig"
        IMMICH_HOST  = "localhost"
        IMMICH_PORT  = "3003"

        TZ           = "Europe/Dublin"

        MACHINE_LEARNING_CACHE_FOLDER    = "${NOMAD_ALLOC_DIR}/data/cache"
        MACHINE_LEARNING_MODEL_TTL       = 0 # don't unload the model cache, re-fetching slows down queries a lot
        MACHINE_LEARNING_REQUEST_THREADS = 4
        # add your models from Settings -> Machine Learning here
        MACHINE_LEARNING_PRELOAD__CLIP   = "ViT-B-16-SigLIP-256__webli"
        MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION = "buffalo_l"
      }

      resources {
        memory = 3072
        cpu    = 4000
      }
    }
  }

  // --- Immich Postgres database and Valkey instance ---
  group "backend" {
    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    network {
      port "postgres" {
        to = 5432
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

      # backs up the Postgres database and removes all files in the backup folder which are older than 3 days.
      action "backup-postgres" {
        command = "/bin/sh"
        args    = ["-c", <<EOF
pg_dumpall -U "$POSTGRES_USER" | gzip --rsyncable > /var/lib/postgresql/data/backup/backup.$(date +"%Y%m%d%H%M").sql.gz
echo "cleaning up backup files older than 3 days ..."
find /var/lib/postgresql/data/backup -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | tail -n +4 | cut -d' ' -f2- | xargs -r rm --
EOF
        ]
      }

      config {
         image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3"

         force_pull = true
      }

      env {
        TZ = "Europe/Dublin"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = 400
        data        = <<EOH
{{- with nomadVar "nomad/jobs/immich" }}
POSTGRES_PASSWORD    = {{- .db_pass }}
POSTGRES_USER        = {{- .db_user }}
DB_URL               = postgres://{{- .db_user }}:{{- .db_pass }}@127.0.0.1:5432/immich
POSTGRES_INITDB_ARGS = '--data-checksums'
{{- end }}
EOH
      }

      volume_mount {
        volume      = "immich-postgres"
        destination = "/var/lib/postgresql/data"
      }

      resources {
        cpu    = 2000
        memory = 1024
      }
    }
 
     # Valkey cache, used as an event queue to schedule jobs
    task "valkey" {
      driver = "docker"

      config {
        image = "valkey/valkey:8.1"
        force_pull = true

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
      type            = "csi"
      source          = "immich-postgres"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}