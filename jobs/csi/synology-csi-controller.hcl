job "synology-csi-controller" {
  datacenters = ["dc1"]
  type        = "system"

  group "controller" {

    task "plugin" {
      driver = "docker"

      config {
        image        = "synology/synology-csi:v1.2.0"
        privileged   = true

        network_mode = "host"

        mount {
          type     = "bind"
          source   = "/"
          target   = "/host"
          readonly = false
        }

        mount {
          type     = "bind"
          source   = "local/csi.yaml"
          target   = "/etc/csi.yaml"
          readonly = true
        }

        args = [
          "--endpoint",
          "unix://csi/csi.sock",
          "--client-info",
          "/etc/csi.yaml"
        ]
      }
      template {
        data        = <<EOH
---
clients:
  - host: 192.168.0.5
    port: 5000
    https: false
    username: distro
    password: {{ key "synology/csi/password" }}
EOH
      destination = "local/csi.yaml"
      }

      csi_plugin {
        id        = "synology"
        type      = "monolith"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
