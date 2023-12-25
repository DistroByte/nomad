job "nessus" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  group "web" {
    network {
      mode = "host"
      
      port "http" {
        to = 8834
      }
    }

    service {
      name = "nessus"
      port = "http"

      check {
        type     = "tcp"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nessus" {
      driver = "docker"

      config {
        image = "tenable/nessus:latest-ubuntu"
        ports = ["http"]

	#volumes = [
	#  "/data/nessus:/opt/nessus"
	#]
      }

      resources {
        memory = 1000
      }
    }
  }
}
