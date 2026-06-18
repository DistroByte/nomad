---
title: Immich
tags: [services, database]
---

# Immich

Photo management service. Postgres runs as a **primary on hermes** with a **streaming replica on zeus**.

## Backups

Daily at 03:00 via the `immich-backup` periodic job. Dumps are written (gzipped) to the Synology NAS at `dionysus.internal:/volume1/data/immich-postgres-backup/` and retained for 7 days.

To trigger a manual backup immediately:
```
nomad job periodic force immich-backup
```

To restore from a backup (run from a host with psql access):
```
gunzip -c /path/to/backup.sql.gz | psql -h <postgres-host> -U <user> -v ON_ERROR_STOP=0
```

## Failover: Promoting the Zeus Replica

If hermes becomes unavailable or its disk dies:

**1. Find the replica allocation:**
```
nomad job allocs immich
```
Note the alloc ID for the `backend-replica` group.

**2. Promote the replica to primary:**
```
nomad alloc exec -task postgres <alloc-id> psql -U <POSTGRES_USER> -d postgres -c "SELECT pg_promote()"
```

**3. Update `jobs/immich/immich.hcl` — swap the constraints:**
- `backend` group: `value = "hermes"` → `value = "zeus"`, change port to match zeus
- `backend-replica` group: remove or set to `value = "hermes"` (once restored)

**4. Redeploy:**
```
nomad job run jobs/immich/immich.hcl
```

**5. Once hermes is restored**, re-seed it as the new replica: set it up as a `host_volume` node, update the constraint back, and let `replica-init` run `pg_basebackup` automatically on next deploy.

## Nomad Client Config Required

On **hermes** (`/etc/nomad.d/client.hcl`):
```hcl
host_volume "immich-postgres" {
  path      = "/opt/nomad/volumes/immich-postgres"
  read_only = false
}
```

On **zeus** (`/etc/nomad.d/client.hcl`):
```hcl
host_volume "immich-postgres-replica" {
  path      = "/opt/nomad/volumes/immich-postgres-replica"
  read_only = false
}
```

Create both directories and set ownership to `70:70` (postgres UID), then reload Nomad on each node.

## Migration from iSCSI (one-time)

1. `pg_dumpall` from the current running instance
2. Stop Immich
3. Add `immich/db/replicator_password` to Consul KV
4. Register the backup NFS volume: `nomad volume create jobs/immich/immich-postgres-backup.hcl`
5. Deploy the updated job: `nomad job run jobs/immich/immich.hcl`
6. Restore the dump: `psql -v ON_ERROR_STOP=0 -f dump.sql` (some "already exists" role errors are expected)
7. The replica seeds itself automatically via `pg_basebackup` once the primary is healthy
8. Deregister the old iSCSI volume: `nomad volume deregister immich-postgres`
