job "example-job" {
  datacenters = ["dc1"]
  node_pool = "default"

  group "web" {
    count = 1
    volume "example_volume" {
      type            = "csi"
      read_only       = false
      source          = "example"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
    network {
      port "http" {
        static = 8888
        to     = 80
      }
    }

    task "nginx" {
      driver = "docker"
      volume_mount {
        volume      = "example_volume"
        destination = "/config"
        read_only   = false
      }
      config {
        image = "nginxdemos/hello:latest"
        ports = ["http"]
      }
    }
  }
}
