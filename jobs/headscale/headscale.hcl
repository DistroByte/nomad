job "headscale" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  # Pin to hermes — shares the node with Traefik, reducing a network hop
  # for the control-plane HTTPS endpoint.
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "hermes"
  }

  group "headscale" {
    network {
      port "http" {
        to = 8080
      }
    }

    volume "headscale-data" {
      type            = "csi"
      read_only       = false
      source          = "headscale"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "headscale"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.headscale.rule=Host(`headscale.dbyte.xyz`)",
      ]

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "headscale" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image      = "headscale/headscale:latest"
        force_pull = true
        ports      = ["http"]
        command    = "serve"

        mount {
          type     = "bind"
          source   = "local/config.yaml"
          target   = "/etc/headscale/config.yaml"
          readonly = true
        }
      }

      volume_mount {
        volume      = "headscale-data"
        destination = "/var/lib/headscale"
        read_only   = false
      }

      template {
        destination = "local/config.yaml"
        data        = <<EOH
server_url: https://headscale.dbyte.xyz
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090

private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h

dns:
  magic_dns: true
  base_domain: ts.dbyte.xyz
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8

log:
  level: info

database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
