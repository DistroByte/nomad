job "loki" {
  datacenters = ["dc1"]

  constraint {
    attribute = "${attr.cpu.arch}"
    value   = "amd64"
  }

  group "loki" {
    network {
      port "http" {
        static = 3100
    }
  }

  service {
    name = "loki"
    port = "http"
  }

  task "loki" {
    driver = "docker"
    config {
      image = "grafana/loki"
      ports = ["http"]

      args = [
        "-config.file",
        "local/loki.yml",
      ]
    }

    template {
      destination = "local/loki.yml"
      data = <<EOF
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  http_server_read_timeout: 600s
  http_server_write_timeout: 600s

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

storage_config:
  filesystem:
    directory: /loki/chunks

querier:
  max_concurrent: 2048
query_scheduler:
  max_outstanding_requests_per_tenant: 2048

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

compactor:
  working_directory: /loki/retention
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: filesystem

limits_config:
  retention_period: 180d
  max_query_series: 100000
EOF
      }
      
      resources {
        cpu    = 512
        memory = 130
      }
    }
  }
}
