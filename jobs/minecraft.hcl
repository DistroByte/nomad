job "minecraft" {
  datacenters = ["dc1"]
  type        = "service"

  group "mc" {
    count = 1
    network {
      port "mc-vanilla-port" {
        to     = 25565
        static = 25565
      }
      port "mc-vanilla-rcon" {
        to     = 25575
        static = 25575
      }
      mode = "bridge"
    }

    task "minecraft-server" {
      driver = "docker"
      config {
        image = "itzg/minecraft-server"
        ports = ["mc-vanilla-port", "mc-vanilla-rcon"]

        volumes = [
          "/data/mintraft:/data"
        ]
      }

      resources {
        cpu    = 3000 # 500 MHz
        memory = 6144 # 6gb
      }

      env {
        EULA   = "TRUE"
        MEMORY = "6G"
      }
    }
  }
}
