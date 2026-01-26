job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "hermes"
  }
  group "traefik" {
    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 8081
      }
      port "voice" {
        static = 64738
      }
    }

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-http"
      port = "admin"
    }

    task "traefik" {
      driver = "docker"
      config {
        image        = "traefik:latest"
        network_mode = "host"

        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
          "local/traefik_dynamic.toml:/etc/traefik/traefik_dynamic.toml"
        ]
      }

      template {
        data        = <<EOF
CLOUDFLARE_API_KEY={{ key "cloudflare/key" }} 
CLOUDFLARE_EMAIL={{ key "cloudflare/email" }}
NS1_API_KEY={{ key "ns1/key" }}
EOF
        destination = "local/env"
        env         = true
      }

      template {
        data = <<EOF
[log]
  level = "INFO"

[metrics]
  [metrics.prometheus]

[api]
  dashboard = true
  insecure = true

[entryPoints]
  [entryPoints.web]
  address = ":80"

  [entryPoints.web.http.redirections.entryPoint]
    to = "websecure"
    scheme = "https"

  [entryPoints.websecure]
    address = ":443"
    asDefault = true

  [entryPoints.websecure.forwardedHeaders]
    trustedIPs = ["127.0.0.1/32", "192.168.0.0/16"]

    [entryPoints.websecure.http.tls]
      certresolver = "cloudflare"

    [[entryPoints.websecure.http.tls.domains]]
      main = "james-hackett.ie"
      sans = ["*.james-hackett.ie"]

    [[entryPoints.websecure.http.tls.domains]]
      main = "dbyte.xyz"
      sans = ["*.dbyte.xyz"]

    [[entryPoints.websecure.http.tls.domains]]
      main = "ihatenixos.org"
      sans = "*.ihatenixos.org"

    [[entryPoints.websecure.http.tls.domains]]
      main = "pint.ing"
      sans = "*.pint.ing"

    [[entryPoints.websecure.http.tls.domains]]
      main = "crazybitta.biz"
      sans = "*.crazybitta.biz"

    [[entryPoints.websecure.http.tls.domains]]
      main = "nicecocks.biz"
      sans = "*.nicecocks.biz"

  [entryPoints.traefik]
    address = ":8081"

  [entryPoints.voice-tcp]
    address = ":64738"
  
  [entryPoints.voice-udp]
    address = ":64738/udp"
    [entryPoints.voice-udp.udp]
      timeout = "15s" # this will help reduce random dropouts in audio https://github.com/mumble-voip/mumble/issues/3550#issuecomment-441495977

[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  [providers.consulCatalog.endpoint]
    address = "127.0.0.1:8500"
    scheme  = "http"

[providers.nomad]
  prefix = "traefik"
  exposedByDefault = false
  [providers.nomad.endpoint]
    address = "http://127.0.0.1:4646"

[certificatesResolvers.cloudflare.acme]
  email = "jamesthackett1@gmail.com"
  storage = "{{ env "NOMAD_ALLOC_DIR" }}/data/acme.json"
  [certificatesResolvers.cloudflare.acme.dnsChallenge]
    provider = "cloudflare"

[providers.file]
  filename = "local/traefik_dynamic.toml"
EOF

        destination = "local/traefik.toml"
      }

      template {
        data = <<EOH
[http.routers.synophotos]
  rule = "Host(`photos.dbyte.xyz`)"
  service = "synophotos"

[[http.services.synophotos.loadBalancer.servers]]
  url = "http://192.168.0.5:5007/"

[http.routers.synodrive]
  rule = "Host(`drive.dbyte.xyz`)"
  service = "synodrive"

[[http.services.synodrive.loadBalancer.servers]]
  url = "http://192.168.0.5:5002/"

[http.routers.video]
  rule = "Host(`video.dbyte.xyz`)"
  service = "video"

[[http.services.video.loadBalancer.servers]]
  url = "http://192.168.0.5:8096/"

[http.routers.photo-activitypub]
  rule = "Host(`photo.james-hackett.ie`) && PathPrefix(`/.ghost/activitypub/`)"
  service = "ghost-activitypub"
  priority = 200

[http.routers.photo-wellknown]
  rule = "Host(`photo.james-hackett.ie`) && PathRegexp(`^/.well-known/(webfinger|nodeinfo)$`)"
  service = "ghost-activitypub"  
  priority = 200

[[http.services.ghost-activitypub.loadBalancer.servers]]
  url = "https://ap.ghost.org"
EOH

        destination = "local/traefik_dynamic.toml"
      }
    }
  }
}
