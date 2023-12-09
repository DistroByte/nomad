job "nessus" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "web" {
    network {
      port "http" {
        to = 8834
      }
    }

    service {
      name = "nessus"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nessus.rule=Host(`nessus.services.consul`)",
        "traefik.http.routers.nessus.entrypoints=websecure",
        "traefik.http.routers.nessus.tls.certresolver=lets-encrypt"
      ]
    }

    task "nessus" {
      driver = "docker"

      config {
        image = "tenable/nessus:latest-ubuntu"
        ports = ["http"]

      }

      resources {
        memory = 800
      }
    }
  }
}
