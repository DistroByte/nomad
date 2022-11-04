job "blog" {
  datacenters = ["dc1"]
  type = "service"
  
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
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "2s"
      }

      tags = [
        "traefik.enable=true",
	"traefik.http.routers.blog.rule=Host(`blog.dbyte.xyz`)",
	"traefik.http.routers.blog.entrypoints=websecure",
	"traefik.http.routers.blog.tls=true",
	"traefik.http.routers.blog.tls.certresolver=lets-encrypt"
      ]
    }

    task "blog" {
      driver = "docker"

      config {
        image = "nginx"
	ports = ["http"]

	mount {
	  type = "bind"
          target = "/usr/share/nginx/html"
          source = "/data/blog/_site"
          readonly = true
	}
	
	mount {
	  type = "bind"
          target = "/etc/nginx/conf.d/default.conf"
          source = "/data/blog/default.conf"
          readonly = true
	}
      }
    }
  }
}
