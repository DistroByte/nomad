job "unifi" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "zeus"
  }

  group "unifi" {
    network {
      port "unifi1" {
        static = 3478
      }
      port "unifi2" {
        static = 10001
      }
      port "http" {
        static = 8080
      }
      port "https" {
        static = 8443
      }
    }

    service {
      name = "unifi"
      port = "https"

      check {
        type     = "http"
        path     = "/manage/account/login"
        interval = "60s"
        timeout  = "5s"
      }
    }

    task "unifi" {
      driver = "docker"
      config {
        image        = "ghcr.io/linuxserver/unifi-controller"
        network_mode = "host"

        volumes = [
          "/data/unifi/config:/config"
        ]
      }

      template {
        env  = true
        data = <<EOH
PGID=1000
PUID=1000
EOH

        destination = "local/file.env"
      }

      resources {
        cpu    = 1000
        memory = 1500
      }
    }
  }
}
