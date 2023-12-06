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
    count = 2

    network {
      port "api" {
        to = 8080
      }
      port "http" {
        to = 80
      }
    }

    update {
      max_parallel = 1
      canary       = 1
    }

    service {
      name = "prospector"
      port = "http"

      check {
        name     = "global_check"
        type     = "http"
        interval = "10s"
        timeout  = "2s"
        path     = "/"
      }
    }

    task "prospector-api" {
      driver = "docker"

      config {
        image = "git.dbyte.xyz/distro/prospector/api:latest"
        ports = ["api"]
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
        cpu    = 128
        memory = 128
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

        canary_tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-frontend-canary.rule=Host(`canary.prospector.ie`)",
          "traefik.http.routers.prospector-frontend-canary.entrypoints=websecure",
          "traefik.http.routers.prospector-frontend-canary.tls.certresolver=lets-encrypt"
        ]

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prospector-frontend.rule=Host(`prospector.ie`)",
          "traefik.http.routers.prospector-frontend.entrypoints=websecure",
          "traefik.http.routers.prospector-frontend.tls.certresolver=lets-encrypt"
        ]
      }

      resources {
        cpu    = 128
        memory = 128
      }
    }
  }
}

