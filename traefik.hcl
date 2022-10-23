job "traefik" {
  datacenters = ["dc1"]
  type        = "system"

  group "traefik" {
    network {
      port "http"{
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin"{
        static = 8081
      }
    }

    service {
      name = "traefik-http"
      port = "https"
    }

    task "traefik" {
      driver = "docker"
      config {
        image = "traefik:2.8"
        network_mode = "host"
        
        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
        ]
      }

      template {
        data = <<EOF
[entryPoints]
  [entryPoints.web]
  address = ":80"
  [entryPoints.web.http.redirections.entryPoint]
    to = "websecure"
    scheme = "https"

  [entryPoints.websecure]
  address = ":443"

  [entryPoints.traefik]
  address = ":8081"

[api]
  dashboard = true
  insecure  = true
  debug = true

[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  [providers.consulCatalog.endpoint]
    address = "127.0.0.1:8500"
    scheme  = "http"

[providers.nomad]
  prefix = "traefik"
  [providers.nomad.endpoint]
    address = "http://127.0.0.1:4646"

[certificatesResolvers.lets-encrypt.acme]
  email = "jamesthackett1@gmail.com"
  storage = "local/acme.json"
  [certificatesResolvers.lets-encrypt.acme.tlsChallenge]

EOF
        destination = "/local/traefik.toml"
      }
    }
  }
}
