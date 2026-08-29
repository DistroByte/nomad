# Stopgap. Ubiquiti is deprecating the standalone Network Application in favour
# of UniFi OS Server, which cannot run as a container — it needs systemd as PID 1
# and host services for device discovery. LinuxServer maintain this image only
# while Ubiquiti keeps publishing the install packages. The exit is a UniFi
# gateway, which runs UniFi OS natively and hosts the controller itself.
job "unifi" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  # Pinned to zeus, not hermes: Traefik owns :8443 there for the
  # websecure-proxied entrypoint, which is also the UniFi UI's default port.
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "zeus"
  }

  group "unifi" {
    # Host networking so UniFi sees the L2 broadcasts devices use to announce
    # themselves, and so STUN reaches them without NAT in the way. Adoption
    # still works without it via `set-inform`, but discovery does not.
    network {
      mode = "host"

      port "https" {
        static = 8443
      }

      port "inform" {
        static = 8080
      }

      port "stun" {
        static = 3478
      }

      port "discovery" {
        static = 10001
      }
    }

    volume "unifi-data" {
      type            = "csi"
      read_only       = false
      source          = "unifi"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "unifi-mongo" {
      type            = "csi"
      read_only       = false
      source          = "unifi-mongo"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "unifi"
      port = "https"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.unifi.rule=Host(`unifi.dbyte.xyz`)",
        # The UI is HTTPS with a self-signed certificate, so Traefik has to
        # speak TLS to it and skip verification (serversTransport in
        # traefik_dynamic.toml).
        "traefik.http.services.unifi.loadbalancer.server.scheme=https",
        "traefik.http.services.unifi.loadbalancer.serverstransport=insecure@file",
        "molecule.icon=https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/png/unifi.png",
      ]

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "mongo" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        image = "mongo:7.0"
        # Bound to loopback deliberately: host networking would otherwise put an
        # unauthenticated-on-first-boot database on the LAN.
        args = ["--bind_ip", "127.0.0.1"]

        network_mode = "host"

        mount {
          type     = "bind"
          source   = "local/init-mongo.js"
          target   = "/docker-entrypoint-initdb.d/init-mongo.js"
          readonly = true
        }
      }

      volume_mount {
        volume      = "unifi-mongo"
        destination = "/data/db"
        read_only   = false
      }

      # Only runs against an empty data directory, so it seeds the user once and
      # is a no-op on every restart thereafter.
      template {
        destination = "local/init-mongo.js"
        data        = <<EOH
db.getSiblingDB("unifi").createUser({
  user: "unifi",
  pwd: "{{ key "unifi/mongo-password" }}",
  roles: [
    { role: "dbOwner", db: "unifi" },
    { role: "dbOwner", db: "unifi_stat" }
  ]
});
EOH
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }

    task "unifi" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image        = "lscr.io/linuxserver/unifi-network-application:latest"
        force_pull   = true
        network_mode = "host"
      }

      volume_mount {
        volume      = "unifi-data"
        destination = "/config"
        read_only   = false
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOH
PUID=1000
PGID=1000
TZ=Europe/Dublin
MONGO_HOST=127.0.0.1
MONGO_PORT=27017
MONGO_DBNAME=unifi
MONGO_AUTHSOURCE=unifi
MONGO_USER=unifi
MONGO_PASS={{ key "unifi/mongo-password" }}
MEM_LIMIT=1024
MEM_STARTUP=1024
EOH
      }

      resources {
        cpu    = 500
        memory = 1280
      }
    }
  }
}
