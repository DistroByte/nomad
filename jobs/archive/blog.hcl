job "blog" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "blog"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.blog.rule=Host(`blog.dbyte.xyz`)",
      ]
    }

    task "blog" {
      driver = "docker"

      config {
        image = "nginx"
        ports = ["http"]

        volumes = [
          "/backups/blog/default.conf:/etc/nginx/conf.d/default.conf",
          "/data/blog/_site:/usr/share/nginx/html"
        ]
      }

      resources {
        memory = 50
      }
    }
  }
}
