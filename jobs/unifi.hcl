job "unifi" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "zeus"
  }

  group "unifi" {
    network {
      # ports sourced from here: https://github.com/linuxserver/docker-unifi-network-application#parameters

      port "unifi-stun" {
        static = 3478
      }
      port "ap-discover" {
        static = 10001
      }
      port "http" {
        static = 8080
      }
      port "https" {
        static = 8443
      }
      port "db" {
	static = 27017
      }
    }

    service {
      name = "unifi"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "60s"
        timeout  = "5s"
      }
    }

    task "unifi" {
      driver = "docker"
      config {
        image = "ghcr.io/linuxserver/unifi-network-application"
	network_mode = "host"

        volumes = [
          "/data/unifi-network-controller/config:/config"
        ]
      }

      template {
        env  = true
        data = <<EOH
PGID=1000
PUID=1000
TZ=Europe/Dublin
MONGO_USER={{ key "unifi/db/user" }}
MONGO_PASS={{ key "unifi/db/pass" }}
MONGO_HOST={{ env "NOMAD_IP_db" }}
MONGO_PORT={{ env "NOMAD_HOST_PORT_db" }}
MONGO_DBNAME=unifi
MEM_LIMIT=1200
MEM_STARTUP=1000
EOH

        destination = "local/file.env"
      }

      resources {
        cpu    = 1000
        memory = 1300
      }
    }

    task "unifi-db" {
      driver = "docker"
      config {
        image = "mongo:4.4"
	ports = ["db"]

        volumes = [
          "unifi-network-controller-db:/data/db",
	  "/data/unifi-network-controller/init-mongo.js:/docker-entrypoint-initdb.d/init-mongo.js:ro"
        ]
      }
    }
  }
}
