job "mumble-cert-renew" {
  datacenters = ["dc1"]
  type        = "batch"

  # murmur only reads its TLS cert at startup, so it will not pick up a renewed
  # cert on its own. This monthly restart re-runs mumble's prestart lego task
  # (which renews once inside the 30-day window) and reloads murmur with the new
  # cert. LE certs last 90 days, so a monthly bounce comfortably covers renewal.
  periodic {
    crons            = ["0 5 1 * *"]
    prohibit_overlap = true
  }

  group "renew" {
    task "restart" {
      driver = "docker"

      config {
        image      = "hashicorp/nomad:latest"
        entrypoint = ["/bin/sh"]
        args       = ["-c", "nomad job restart -reschedule -yes mumble"]
      }

      env {
        # Talk to the local Nomad client agent on whichever node this batch lands.
        NOMAD_ADDR = "http://${attr.unique.network.ip-address}:4646"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
