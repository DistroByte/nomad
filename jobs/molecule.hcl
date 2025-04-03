job "molecule" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "server" {
    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "molecule"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.molecule.rule=Host(`molecule.dbyte.xyz`)",
      ]
    }

    task "molecule" {
      driver = "docker"

      template {
        data        = <<EOF
PROD=true
API_KEY={{ key "molecule/apikey" }}
EOF
        destination = "local/env"
        env         = true
      }

      config {
        image = "ghcr.io/distrobyte/molecule:latest"
        ports = ["http"]
      }
      
      resources {
        cpu    = 200
        memory = 100
      }
    }
  }
}
