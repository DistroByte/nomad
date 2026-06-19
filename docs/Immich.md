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
