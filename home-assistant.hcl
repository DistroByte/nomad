job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  group "home-automation" {
    count = 1 
    network {
      port "http" { 
	static = "8123" 
      }
    }

    task "hass" {
      driver = "docker"
      config {
        image = "homeassistant/home-assistant"
        network_mode = "host"
        volumes = [
          "/data/home-assistant:/config",
        ]
        privileged = true
      }

      service {
        port = "http"
	name = "hass"
        
	tags = [
          "traefik.enable=true",
          "traefik.http.middlewares.httpsRedirect.redirectscheme.scheme=https",
          "traefik.http.routers.homeassistant.rule=Host(`ha.dbyte.xyz`)",
          "traefik.http.routers.homeassistant.tls.domains[0].sans=ha.dbyte.xyz",
          "traefik.http.routers.homeassistant.tls.certresolver=lets-encrypt",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
