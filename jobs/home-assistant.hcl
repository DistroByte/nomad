job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "home-automation" {
    count = 1
    network {
      port "http" {
        static = "8123"
      }
      port "z2mhttp" {
        to = "8080"
      }
      port "mqtthttp" {
        static = "9001"
      }
      port "mqttdisc" {
        static = "1883"
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
      config {
        image        = "homeassistant/home-assistant"
        network_mode = "host"
        privileged   = true
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
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "mqtt" {
      driver = "docker"
      config {
        image        = "eclipse-mosquitto"
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
      }
    }

    task "zigbee2mqtt" {
      driver = "docker"
      config {
        image      = "koenkk/zigbee2mqtt"
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
  }
}
