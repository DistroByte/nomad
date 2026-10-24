job "scrapbook" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
        to = 2368
      }
    }

    volume "scrapbook-data" {
      type            = "csi"
      read_only       = false
      source          = "scrapbook"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    service {
      name = "scrapbook"
      port = "http"

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.scrapbook.rule=Host(`scrapbook.james-hackett.ie`)",
        "icon=https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/bookstack.svg"
      ]
    }

    task "website" {
      driver = "docker"

      config {
        image = "ghost:6.71.0"
        ports = ["http"]
      }

      volume_mount {
        volume      = "scrapbook-data"
        destination = "/var/lib/ghost/content"
        read_only   = false
      }

      template {
        data        = <<EOF
url = "https://scrapbook.james-hackett.ie"
database__client = "sqlite3"
database__connection__filename = "/var/lib/ghost/content/data/ghost.db"
logging__level = "info"
logging__transports = "[\"stdout\"]"
privacy__useTinfoil = "true"
security__staffDeviceVerification="false"
mail__from = "support@distrobyte.io"
mail__transport="SMTP"
mail__options__service="Google"
mail__options__host={{ key "mail/google/host" }}
mail__options__port="465"
mail__options__secure="true"
mail__options__auth__user="{{ key "mail/vaultwarden/username" }}"
mail__options__auth__pass="{{ key "mail/vaultwarden/password" }}"
EOF
        destination = "local/ghost.env"
        env         = true
      }

      resources {
        cpu    = 600
        memory = 700
      }
    }
  }
}
