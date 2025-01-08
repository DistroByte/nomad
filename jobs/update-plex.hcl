job "plex-update" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["@weekly"]
    prohibit_overlap = true
  }

  group "plex-update" {

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "zeus"
    }

    task "update-plex" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data = <<EOH
#/bin/bash

ssh -i /home/distro/.ssh/id_ed25519 -oStrictHostKeyChecking=no root@192.168.0.5 "/usr/local/bin/docker container restart plex"
EOH

        destination = "local/script.sh"
      }
    }
  }
}
