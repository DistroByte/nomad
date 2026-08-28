job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    auto_revert = true
  }

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

      port "https_proxied" {
        static = 8443
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

      check {
        type     = "http"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"
      shutdown_delay = "5s"
      config {
        image        = "traefik:latest"
        force_pull   = true
        network_mode = "host"

        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
          "local/traefik_dynamic.toml:/etc/traefik/traefik_dynamic.toml",
          "local/mediashare.htpasswd:/etc/traefik/mediashare.htpasswd"
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
        data        = <<EOF
{{ key "mediashare/htpasswd" }}
EOF
        destination = "local/mediashare.htpasswd"
        perms       = "400"
      }

      template {
        data = <<EOF
[log]
  level = "INFO"

# No filePath, so this goes to stdout and `nomad alloc logs -job traefik`
# surfaces it. ClientHost is the field that matters now that requests arrive
# through the off-site relay: it should show the real client address rather
# than the relay's 100.64.0.0/10 tailnet IP. If it ever shows the latter,
# PROXY protocol has stopped being honoured on websecure-proxied.
[accessLog]
  format = "json"

  [accessLog.fields.headers]
    defaultMode = "drop"

    [accessLog.fields.headers.names]
      User-Agent = "keep"

[metrics]
  [metrics.prometheus]

[api]
  dashboard = true
  insecure = true

[ping]
  entryPoint = "traefik"

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
      sans = ["*.ihatenixos.org"]

    [[entryPoints.websecure.http.tls.domains]]
      main = "crazybitta.biz"
      sans = ["*.crazybitta.biz"]

    [[entryPoints.websecure.http.tls.domains]]
      main = "nicecocks.biz"
      sans = ["*.nicecocks.biz"]

  # Ingress from the off-site relays. They pass TCP through at L4 and prepend a
  # PROXY protocol header, so the real client address survives; without this
  # entrypoint every request would appear to come from the relay's tailnet IP.
  # asDefault keeps existing routers serving here with no per-service changes.
  [entryPoints.websecure-proxied]
    address = ":8443"
    asDefault = true

    [entryPoints.websecure-proxied.proxyProtocol]
      trustedIPs = ["100.64.0.0/10"]

    [entryPoints.websecure-proxied.forwardedHeaders]
      trustedIPs = ["100.64.0.0/10"]

    [entryPoints.websecure-proxied.http.tls]
      certresolver = "cloudflare"

    [[entryPoints.websecure-proxied.http.tls.domains]]
      main = "james-hackett.ie"
      sans = ["*.james-hackett.ie"]

    [[entryPoints.websecure-proxied.http.tls.domains]]
      main = "dbyte.xyz"
      sans = ["*.dbyte.xyz"]

    [[entryPoints.websecure-proxied.http.tls.domains]]
      main = "ihatenixos.org"
      sans = ["*.ihatenixos.org"]

    [[entryPoints.websecure-proxied.http.tls.domains]]
      main = "crazybitta.biz"
      sans = ["*.crazybitta.biz"]

    [[entryPoints.websecure-proxied.http.tls.domains]]
      main = "nicecocks.biz"
      sans = ["*.nicecocks.biz"]

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

[certificatesResolvers.ns1.acme]
  email = "james@distrobyte.io"
  storage = "{{ env "NOMAD_ALLOC_DIR" }}/data/acme-ns1.json"
  [certificatesResolvers.ns1.acme.dnsChallenge]
    provider = "ns1"
    resolvers = ["1.1.1.1:53", "8.8.8.8:53"]

[providers.file]
  filename = "local/traefik_dynamic.toml"
EOF

        destination = "local/traefik.toml"
      }

      template {
        data = <<EOH
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

[http.middlewares.mediashare-auth.basicAuth]
  usersFile = "/etc/traefik/mediashare.htpasswd"
EOH

        destination = "local/traefik_dynamic.toml"
      }
    }
  }
}
