job "headscale-export" {
  datacenters = ["dc1"]
  type        = "batch"

  # One-shot: copies headscale's state off the CSI volume so it can be moved to
  # the off-cluster control plane. Stop the headscale job first — the volume is
  # single-node-writer, so this will not place while headscale holds it.
  #
  #   nomad job stop headscale
  #   nomad job run jobs/headscale/headscale-export.hcl
  #   # then, from hermes:
  #   scp /backups/headscale/headscale-state.tar.gz ubuntu@141.147.74.4:/tmp/
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "hermes"
  }

  group "export" {
    volume "headscale-data" {
      type            = "csi"
      read_only       = false
      source          = "headscale"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "export" {
      driver = "docker"

      config {
        image      = "alpine:latest"
        entrypoint = ["/bin/sh"]
        args       = ["/local/export.sh"]

        mount {
          type   = "bind"
          target = "/backup"
          source = "/backups"
        }
      }

      volume_mount {
        volume      = "headscale-data"
        destination = "/data"
        read_only   = true
      }

      template {
        destination = "local/export.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu

mkdir -p /backup/headscale
out="/backup/headscale/headscale-state.tar.gz"

cd /data

echo "volume contents:"
ls -la

# db.sqlite and noise_private.key are the pair that matter: lose either and
# every registered node is orphaned and must re-register by hand. Fail before
# writing anything rather than producing a tarball that looks complete.
for required in db.sqlite noise_private.key; do
  if [ ! -f "$required" ]; then
    echo "FATAL: $required missing from the volume" >&2
    exit 1
  fi
done

# Everything else is best-effort. headscale 0.23+ no longer creates
# private.key, so a fixed file list fails on current deployments.
set -- db.sqlite noise_private.key
for optional in private.key config.yaml policy.hujson; do
  [ -f "$optional" ] && set -- "$@" "$optional"
done
[ -d headplane ] && set -- "$@" headplane

tar czf "$out" "$@"

echo "wrote:"
ls -l "$out"
echo "contents:"
tar tzf "$out"
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
