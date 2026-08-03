job "mumble" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "voice" {
    network {
      port "voice-udp" {
        to = 64738
      }
    }

    service {
      port = "voice-udp"

      tags = [
        "traefik.enable=true",
        "traefik.tcp.routers.mumble-tcp.rule=HostSNI(`mumble.dbyte.xyz`)",
        "traefik.tcp.routers.mumble-tcp.tls.passthrough=true",
        "traefik.tcp.routers.mumble-tcp.entrypoints=voice-tcp",
        "traefik.udp.routers.mumble-udp.entrypoints=voice-udp",
        "prometheus.io/scrape=false"
      ]

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    # Obtains/renews a real Let's Encrypt cert for mumble.dbyte.xyz via Cloudflare
    # DNS-01 before murmur starts, writing to the /data NFS share (visible on both
    # nodes). murmur presents it directly because the Traefik TCP router uses TLS
    # passthrough.
    task "cert" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image      = "goacme/lego:latest"
        force_pull = false
        entrypoint = ["/bin/sh"]
        args       = ["/local/lego.sh"]

        mount {
          type   = "bind"
          target = "/certs"
          source = "/data/mumble-certs"
        }
      }

      template {
        destination = "secrets/lego.env"
        env         = true
        perms       = "400"
        data        = <<EOH
CLOUDFLARE_EMAIL = {{ key "cloudflare/email" }}
CLOUDFLARE_API_KEY = {{ key "cloudflare/key" }}
EOH
      }

      template {
        destination = "local/lego.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

LEGO=$(command -v lego || echo /lego)
DOMAIN=mumble.dbyte.xyz
CERTPATH=/certs

# Query public resolvers directly for the propagation check so the container's
# Docker/Pi-hole resolver chain can't return NODATA for the challenge record.
if [ -f "$CERTPATH/certificates/$DOMAIN.crt" ]; then
  "$LEGO" --accept-tos --email "$CLOUDFLARE_EMAIL" \
    --dns cloudflare --dns.resolvers 1.1.1.1:53 --dns.resolvers 8.8.8.8:53 \
    --domains "$DOMAIN" --path "$CERTPATH" \
    renew --days 30 --no-random-sleep
else
  "$LEGO" --accept-tos --email "$CLOUDFLARE_EMAIL" \
    --dns cloudflare --dns.resolvers 1.1.1.1:53 --dns.resolvers 8.8.8.8:53 \
    --domains "$DOMAIN" --path "$CERTPATH" \
    run
fi

# murmur may run as a non-root user; make the cert/key readable. Non-fatal since
# NFS root-squash can reject the chmod without the files being unreadable.
chmod -R a+rX "$CERTPATH" || true
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "mumble" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image      = "mumblevoip/mumble-server:latest"
        force_pull = true
        ports      = ["voice-udp"]

        hostname = "mumble.dbyte.xyz"

        mount {
          type     = "bind"
          target   = "/certs"
          source   = "/data/mumble-certs"
          readonly = true
        }
      }

      template {
        data        = <<EOF
MUMBLE_SUPERUSER_PASSWORD={{ key "mumble/admin/password" }}
MUMBLE_CONFIG_WELCOMETEXT="Ahh! SuperNintendo Chalmers!"
MUMBLE_CONFIG_ALLOWHTML=true
MUMBLE_CONFIG_SSLCERT=/certs/certificates/mumble.dbyte.xyz.crt
MUMBLE_CONFIG_SSLKEY=/certs/certificates/mumble.dbyte.xyz.key
EOF
        destination = "local/env"
        env         = true
      }

      resources {
        cpu    = 300
        memory = 100
      }
    }
  }
}
