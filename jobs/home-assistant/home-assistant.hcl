job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "home-automation" {
    count = 1
    network {
      port "http" {
        static = 8123
      }
      port "z2mhttp" {
        to = 8080
      }
      port "mqtthttp" {
        static = 9001
      }
      port "mqttdisc" {
        static = 1883
      }
    }

    volume "homeassistant-data" {
      type            = "csi"
      read_only       = false
      source          = "homeassistant"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "z2m-data" {
      type            = "csi"
      read_only       = false
      source          = "z2m"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "mqtt-data" {
      type            = "csi"
      read_only       = false
      source          = "mqtt"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "hass" {
      driver = "docker"
      shutdown_delay = "5s"
      kill_timeout   = "30s"
      config {
        image        = "homeassistant/home-assistant:latest"
        force_pull   = true
        network_mode = "host"
        privileged   = true

        # HA's automatic backups write to /config/backups, i.e. the same LUN they
        # protect. Redirect them to the /backups NFS share so they survive loss of
        # the homeassistant Synology LUN.
        mount {
          type   = "bind"
          target = "/config/backups"
          source = "/backups/home-assistant"
        }
      }

      volume_mount {
        volume      = "homeassistant-data"
        destination = "/config"
        read_only   = false
      }

      resources {
        cpu    = 800
        memory = 800
      }

      service {
        port = "http"
        name = "hass"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.homeassistant.rule=Host(`ha.dbyte.xyz`)",
          "traefik.http.routers.homeassistant.tls.domains[0].sans=ha.dbyte.xyz",
          "icon=https://github.com/homarr-labs/dashboard-icons/blob/main/png/home-assistant.png?raw=true"
        ]

        check {
          type     = "http"
          path     = "/manifest.json"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "mqtt" {
      driver = "docker"
      shutdown_delay = "5s"
      config {
        image        = "eclipse-mosquitto:latest"
        force_pull   = true
        network_mode = "host"
        command      = "mosquitto"
        args         = ["-c", "/mosquitto-no-auth.conf"]
      }

      volume_mount {
        volume      = "mqtt-data"
        destination = "/mosquitto"
        read_only   = false
      }

      env {
        TZ = "Europe/Dublin"
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name = "mqtt"
        port = "mqttdisc"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "zigbee2mqtt" {
      driver = "docker"
      shutdown_delay = "5s"
      config {
        image      = "koenkk/zigbee2mqtt:latest"
        force_pull = true
        privileged = true
        ports      = ["z2mhttp"]

        volumes = [
          "/run/udev:/run/udev:ro"
        ]

        devices = [
          {
            host_path      = "/dev/ttyACM0"
            container_path = "/dev/ttyACM0"
          }
        ]
      }

      volume_mount {
        volume      = "z2m-data"
        destination = "/app/data"
        read_only   = false
      }

      env {
        TZ = "Europe/Dublin"
      }

      resources {
        cpu    = 100
        memory = 300
        device "1cf1/usb/0030" {}
      }
    }

    # Daily off-LUN backup of the Zigbee2MQTT data (network keys, device database,
    # coordinator backup) to the /backups NFS share, so losing the z2m Synology LUN
    # doesn't mean re-pairing every device. Runs in-alloc because the LUN is
    # single-node-writer and can't be co-mounted from a separate job.
    task "z2m-backup" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image      = "alpine:latest"
        entrypoint = ["/bin/sh"]
        args       = ["/local/backup.sh"]

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups/zigbee2mqtt"
        }
      }

      volume_mount {
        volume      = "z2m-data"
        destination = "/z2m-data"
        read_only   = true
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
# No `set -e`: a transient tar failure must not kill the sidecar and cascade to
# the alloc. Log and keep looping instead.
while true; do
  stamp=$(date +%Y%m%d%H%M)
  if tar czf "/backup/z2m.$stamp.tar.gz" -C /z2m-data . ; then
    # Keep the 14 most recent archives.
    ls -1t /backup/z2m.*.tar.gz 2>/dev/null | tail -n +15 | while read -r old; do
      rm -f "$old"
    done
  else
    echo "z2m backup failed at $stamp" >&2
  fi
  sleep 86400
done
EOH
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
