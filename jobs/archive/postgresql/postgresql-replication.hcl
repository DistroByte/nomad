job "postgres-replication" {
  datacenters = ["dc1"]

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "db" {
    network {
      port  "db"{
        static = 5432
      }
    }

    task "postgresql-db" {
      driver = "docker"

      count = 2
      
      template {
	data = <<EOH

        POSTGRES_PASSWORD="{{ key "postgresql/password/root" }}"
	POSTGRES_USER="root"
	EOH
	
	destination = "local/file.env"
	env = true
      }

      config {
        image = "postgres:latest"
        ports = ["db"]

	volumes = [
	  "local/postgresql.conf:/etc/postgres/postgresql.conf",
	  "local/pg_hba.conf:/pg_hba.conf",
	  "local/pg_ident.conf:/pg_ident.conf"
	]
      }

      template {
        data = <<EOH
max_connections = 100
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 5242kB
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2

#replication
wal_level = logical
wal_log_hints = on # allows standby to catch up to master
max_wal_senders = 8
max_wal_size = 1GB
hot_standby = on

hba_file = "/pg_hba.conf"
ident_file = "/pg_ident.conf"
EOH

        destination = "local/postgresql.conf"
      }

      template {
        data = <<EOH
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host 	all 		all 		all 			scram-sha-256
local 	homeassistant 	homeassistant 				peer
EOH
        destination = "local/pg_hba.conf"
      }

      template {
        data = <<EOH
map-name root homeassistant
EOH
        destination = "/local/pg_ident.conf"
      }

      service {
        name = "postgresql"
        port = "db"

        check {
          type     = "tcp"
          interval = "2s"
          timeout  = "2s"
        }
      }
    }
  }
}
