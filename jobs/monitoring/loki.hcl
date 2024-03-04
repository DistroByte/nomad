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

    tags = [
      "traefik.enable=true",
      "traefik.http.routers.loki.entrypoints=web",
      "traefik.http.routers.loki.rule=Host(`loki.service.consul`)"
    ]
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


common:
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  
  replication_factor: 1


  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory


schema_config:
  configs:
    - from: 2020-09-07
      store: boltdb-shipper
      object_store: filesystem
      schema: v12
      index:
        prefix: loki_index_
        period: 24h
EOF
      }
      
      resources {
        cpu    = 512
        memory = 130
      }
    }
  }
}
