job "grafana" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    network {
      port "http" {
	to = 3000
      }
    }

    service {
      name = "grafana"
      port = "http"

      check {
	type = "http"
	path = "/"
	interval = "10s"
	timeout = "2s"
      }
    }

    task "grafana" {
      driver = "docker"

      env {
	GF_AUTH_BASIC_ENABLED = "false"
	GF_INSTALL_PLUGINS = "grafana-piechart-panel"
      }

      config {
        image = "grafana/grafana"
	ports = ["http"]
      }
    }

  }
}

