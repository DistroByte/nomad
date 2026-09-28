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
      port "headscale" {
        to = 8080
      }
      port "headplane" {
        to = 3000
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
      port = "headscale"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.headscale.rule=Host(`headscale.dbyte.xyz`)",
        "molecule.skip=true"
      ]

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "headplane"
      port = "headplane"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.headplane.rule=Host(`headplane.dbyte.xyz`)",
        "traefik.http.routers.headplane.middlewares=headplane-redirect",
        "traefik.http.middlewares.headplane-redirect.redirectregex.regex=^https?://headplane.dbyte.xyz/?$",
        "traefik.http.middlewares.headplane-redirect.redirectregex.replacement=https://headplane.dbyte.xyz/admin",
        "molecule.icon=https://raw.githubusercontent.com/tale/headplane/main/app/logo/dark-bg.svg"
      ]

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    # Seeds headscale config onto the CSI volume on first run.
    # Skips the copy if the file already exists so headplane edits survive redeployments.
    task "init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:latest"
        command = "sh"
        args    = ["-c", "mkdir -p /data/headplane && [ -f /data/config.yaml ] || cp /local/config.yaml /data/config.yaml"]
      }

      volume_mount {
        volume      = "headscale-data"
        destination = "/data"
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
      - 192.168.0.5

log:
  level: info

database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite

policy:
  mode: database
EOH
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }

    task "headscale" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image      = "headscale/headscale:latest"
        force_pull = true
        ports      = ["headscale"]
        command    = "serve"
        args       = ["--config", "/var/lib/headscale/config.yaml"]

        labels = {
          "me.tale.headplane.target" = "headscale"
        }
      }

      volume_mount {
        volume      = "headscale-data"
        destination = "/var/lib/headscale"
        read_only   = false
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "headplane" {
      driver = "docker"

      config {
        image      = "ghcr.io/tale/headplane:latest"
        force_pull = true
        ports      = ["headplane"]

        mount {
          type     = "bind"
          source   = "local/config.yaml"
          target   = "/etc/headplane/config.yaml"
          readonly = true
        }

        mount {
          type   = "bind"
          source = "/var/run/docker.sock"
          target = "/var/run/docker.sock"
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
server:
  host: "0.0.0.0"
  port: 3000
  base_url: "https://headplane.dbyte.xyz"
  cookie_secret: "{{ key "tailscale/headplane/secret" }}"
  cookie_secure: true
  data_path: "/var/lib/headscale/headplane"

headscale:
  url: "http://{{ env "NOMAD_ADDR_headscale" }}"
  config_path: "/var/lib/headscale/config.yaml"

integration:
  docker:
    enabled: true
    socket: "unix:///var/run/docker.sock"
EOH
      }

      resources {
        cpu    = 100
        memory = 200
      }
    }
  }
}
