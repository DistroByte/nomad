job "website" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "website"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.website.rule=Host(`james-hackett.ie`)",
        "icon=https://james-hackett.ie/profile.webp",
      ]
    }

    task "website" {
      driver = "docker"

      action "update-site" {
        command = "/bin/bash"
        args    = ["-c", <<EOF
mv /usr/share/nginx/html/index.html{,.bak}

curl -o /usr/share/nginx/html/index.html https://flowcv.me/james-hackett

if [ -s /usr/share/nginx/html/index.html ]; then
  sed -i 's/<img src="[^>]*" alt="James Hackett" class="sc-gsDKAQ WjBEv">/<img src=".\/profile.webp" alt="James Hackett" class="sc-gsDKAQ WjBEv">/g' /usr/share/nginx/html/index.html
  sed -i 's|<script data-cfasync="false" src="/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>|<script data-cfasync="false" src="https://flowcv.io/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>|' /usr/share/nginx/html/index.html
  echo "$(date) - updated successfully"
else
  mv /usr/share/nginx/html/index.html{.bak,}
  echo "$(date) - update unsuccessful"
fi
EOF
        ]
      }

      config {
        image = "nginx"
        ports = ["http"]

        mount {
          type     = "bind"
          target   = "/usr/share/nginx/html"
          source   = "/data/website/site"
        }
      }

      resources {
        memory = 50
      }
    }
  }
}
