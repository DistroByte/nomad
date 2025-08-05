job "prospector" {
  type        = "service"
  datacenters = ["dc1"]

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  meta {
    git_sha = "d03d36a0"
  }

  group "prospector" {
    count = 1

    network {
      port "api" {
        to = 3434
      }
      port "http" {
        to = 80
      }
    }

    update {
      max_parallel = 1
      canary       = 1
    }

    task "prospector-api" {
      driver = "docker"
      config {
        image = "git.dbyte.xyz/distro/prospector/api:latest"
        ports = ["api"]
      }

      template {
        data        = <<EOF
GIN_MODE=release
EOF
        destination = "local/env"
        env         = true
      }

      service {
        name = "prospector-api"
        port = "api"

        canary_tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-api-canary.rule=Host(`canary.prospector.ie`) && PathPrefix(`/api`)",
          "traefik.http.routers.prospector-api-canary.entrypoints=websecure",
          "traefik.http.routers.prospector-api-canary.tls.certresolver=lets-encrypt"
        ]

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-api.rule=Host(`prospector.ie`) && PathPrefix(`/api`)",
          "traefik.http.routers.prospector-api.entrypoints=websecure",
          "traefik.http.routers.prospector-api.tls.certresolver=lets-encrypt"
        ]

        check {
          type     = "http"
          path     = "/api/health"
          interval = "5s"
          timeout  = "1s"
        }
      }

      resources {
        cpu    = 60
        memory = 60
      }
    }

    task "prospector-frontend" {
      driver = "docker"

      config {
        image = "git.dbyte.xyz/distro/prospector/frontend:latest"
        ports = ["http"]
      }

      service {
        name = "prospector-frontend"
        port = "http"

        check {
          name     = "frontend_check"
          type     = "http"
          interval = "10s"
          timeout  = "2s"
          path     = "/"
        }

        canary_tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-frontend-canary.rule=Host(`canary.prospector.ie`)",
          "traefik.http.routers.prospector-frontend-canary.entrypoints=websecure",
          "traefik.http.routers.prospector-frontend-canary.tls.certresolver=lets-encrypt",
          "prometheus.io/scrape=false"
        ]

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-frontend.rule=Host(`prospector.ie`)",
          "traefik.http.routers.prospector-frontend.entrypoints=websecure",
          "traefik.http.routers.prospector-frontend.tls.certresolver=lets-encrypt",
          "prometheus.io/scrape=false"
        ]
      }

      resources {
        cpu    = 30
        memory = 30
      }
    }
  }
}
