job "ddclient" {
  datacenters = ["dc1"]

  type = "service"

  group "ddclient" {
    task "ddclient" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/ddclient:latest"

	mount {
	  type = "bind"
	  target = "/config"
	  source = "/data/ddclient"
	  readonly = false
	}
      }

      resources {
        memory = 50
      }
    }
  }
}
