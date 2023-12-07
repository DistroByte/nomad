job "prospector-update" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 0 * * * *"]
    prohibit_overlap = true
  }

  group "prospector-update" {
    task "update-site" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data        = <<EOH
#/bin/bash

cd /data/prospector.ie

git pull
EOH
        destination = "local/script.sh"
      }
    }
  }
}
