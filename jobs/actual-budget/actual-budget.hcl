job "actual-budget" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 5006
      }
    }

    volume "actual-budget-data" {
      type            = "csi"
      read_only       = false
      source          = "actual-budget"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "actual-budget"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.actual-budget.rule=Host(`actual.dbyte.xyz`)",
        "prometheus.io/scrape=false",
      ]
    }

    task "actual-budget" {
      driver = "docker"
      shutdown_delay = "5s"

      config {
        image      = "actualbudget/actual-server:latest"
        force_pull = true
        ports      = ["http"]
      }

      volume_mount {
        volume      = "actual-budget-data"
        destination = "/data"
        read_only   = false
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
