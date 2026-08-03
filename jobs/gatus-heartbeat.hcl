job "gatus-heartbeat" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/5 * * * *"]
    prohibit_overlap = true
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "hermes"
  }

  group "heartbeat" {
    restart {
      attempts = 0
    }

    task "ping" {
      driver = "docker"

      config {
        image        = "curlimages/curl:latest"
        network_mode = "host"
        entrypoint   = ["/bin/sh"]
        args         = ["/local/heartbeat.sh"]
      }

      template {
        destination = "secrets/heartbeat.env"
        env         = true
        perms       = "400"
        data        = <<EOH
HEARTBEAT_TOKEN={{ key "gatus/heartbeat-token" }}
EOH
      }

      template {
        destination = "local/heartbeat.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

curl -fsS -X POST --max-time 15 \
  -H "Authorization: Bearer $HEARTBEAT_TOKEN" \
  "http://observability.ts.dbyte.xyz:8080/api/v1/endpoints/core_heartbeat/external?success=true"
EOH
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
