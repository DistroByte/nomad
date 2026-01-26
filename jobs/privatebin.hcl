job "privatebin" {
  datacenters = ["aperture"]

  type = "service"

  group "privatebin" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "privatebin"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.privatebin.rule=Host(`paste.dbyte.xyz`)",
      ]
    }

    task "privatebin" {
      driver = "docker"

      config {
        image = "privatebin/nginx-fpm-alpine:stable"
        ports = ["http"]

        volumes = [
          "local/conf.php:/srv/data/conf.php",
        ]
      }
      env {
        TZ          = "Europe/Dublin"
        PHP_TZ      = "Europe/Dublin"
        CONFIG_PATH = "/srv/data/"
      }

      template {
        destination = "local/conf.php"
        data        = <<EOH
[main]
name = "PasteBin"
basepath = "https://paste.dbyte.xyz/"
discussion = true
opendiscussion = false
password = true
fileupload = true
burnafterreadingselected = false
defaultformatter = "markdown"
syntaxhighlightingtheme = "sons-of-obsidian"
sizelimit = 10485760
template = "bootstrap-dark"
languageselection = false
languagedefault = "en"
qrcode = true
email = true
icon = "identicon"
zerobincompatibility = false
httpwarning = true
compression = "zlib"

[expire]
default = "1week"

[expire_options]
5min = 300
10min = 600
1hour = 3600
1day = 86400
1week = 604800
2week = 1209600
1month = 2592000
1year = 31536000
never = 0

[formatter_options]
plaintext = "Plain Text"
markdown = "Markdown"
syntaxhighlighting = "Source Code"

[traffic]
limit = 10
header = "X-Forwarded-For"

[purge]
limit = 300
batchsize = 10

[model]
class = Database
[model_options]
dsn = "pgsql:host={{ env "NOMAD_IP_db" }};port={{ env "NOMAD_HOST_PORT_db" }};dbname={{ key "privatebin/db/name" }}"
tbl = "{{ key "privatebin/db/name" }}"
usr = "{{ key "privatebin/db/user" }}"
pwd = "{{ key "privatebin/db/password" }}"
opt[12] = true
EOH
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = "postgres:17-alpine"
        ports = ["db"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      template {
        data        = <<EOH
POSTGRES_PASSWORD={{ key "privatebin/db/password" }}
POSTGRES_USER={{ key "privatebin/db/user" }}
POSTGRES_NAME={{ key "privatebin/db/name" }}
EOH
        destination = "local/db.env"
        env         = true
      }
    }
  }
}