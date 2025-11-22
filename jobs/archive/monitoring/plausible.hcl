job "plausible" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    network {
      port "http" {
	to = 8000
      }
      port "db" {
 	to = 8123
      }
    }

    task "plausible" {
      service {
        name = "plausible"
        port = "http"

        check {
          type = "http"
          path = "/index.html"
          interval = "10s"
          timeout = "2s"
        }

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.plausible.rule=Host(`plausible.dbyte.xyz`)",
        ]
      }

      driver = "docker"

      config {
        image = "plausible/analytics:latest"
	ports = ["http"]

	command = "/bin/sh"
	args = ["-c", "sleep 10 && /entrypoint.sh db migrate && /entrypoint.sh run"]
      }

      template {
        data = <<EOH
BASE_URL=https://plausible.dbyte.xyz
SECRET_KEY_BASE={{ key "plausible/secret" }}
DATABASE_URL=postgres://{{ key "plausible/db_user" }}:{{ key "plausible/db_pass" }}@postgresql.service.consul:5432/plausible
CLICKHOUSE_DATABASE_URL=http://{{ env "NOMAD_ADDR_db" }}/plausible_events_db
EOH
	destination = "local/file.env"
	env = true
      }
    }

    task "clickhouse" {
      service {
        name = "plausible-clickhouse"
	port = "db"
      }

      driver = "docker"

      config {
	image = "clickhouse/clickhouse-server:22.6-alpine"
	ports = ["db"]
	volumes = [
	  "local/clickhouse.xml:/etc/clickhouse-server/config.d/logging.xml:ro",
	  "local/clickhouse-user-config.xml:/etc/clickhouse-server/users.d/logging.xml:ro"
	]
      }


      template {
        data = <<EOH
<clickhouse>
    <logger>
        <level>warning</level>
        <console>true</console>
    </logger>

    <!-- Stop all the unnecessary logging -->
    <query_thread_log remove="remove"/>
    <query_log remove="remove"/>
    <text_log remove="remove"/>
    <trace_log remove="remove"/>
    <metric_log remove="remove"/>
    <asynchronous_metric_log remove="remove"/>
    <session_log remove="remove"/>
    <part_log remove="remove"/>
</clickhouse>
EOH
        destination = "local/clickhouse.xml"
      }

      template {
        data = <<EOH
<clickhouse>
    <profiles>
        <default>
            <log_queries>0</log_queries>
            <log_query_threads>0</log_query_threads>
        </default>
    </profiles>
</clickhouse>
EOH
        destination = "local/clickhouse-user-config.xml"
      }
    }
  }
}
