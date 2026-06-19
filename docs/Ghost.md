---
title: Ghost (Photo Site)
tags: [services, database]
---

# Ghost (Photo Site)

Ghost blog running at `photo.james-hackett.ie`. MySQL runs on a **host volume on hermes** (local SSD, not NAS) for I/O performance. Ghost content (themes, images, uploads) remains on a Synology CSI volume.

## Storage Layout

| Volume | Type | Location | Contents |
|---|---|---|---|
| `photo` | CSI (Synology) | NAS | Ghost content: themes, images, files |
| `photo-mysql` | Host volume | hermes `/opt/nomad/volumes/photo-mysql` | MySQL data directory |

## Backups

Daily at 04:00 via the `photo-backup` periodic job. Dumps are written (gzipped) to the NAS at `dionysus.internal:/volume1/data/photo-mysql-backup/` and retained for 7 days.

To trigger a manual backup:
```bash
nomad job periodic force photo-backup
```

To restore from a backup:
```bash
# Get the running alloc
nomad job status photo

# Copy the dump into the database container and restore
nomad alloc exec -task database <alloc-id> \
  sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" < /tmp/backup.sql'
```

## Migrating MySQL Data (Host Volume)

If hermes needs to be rebuilt or the MySQL data needs to be moved:

1. Dump the database before stopping the job:
```bash
nomad alloc exec -task database <alloc-id> \
  sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --no-tablespaces "$MYSQL_DATABASE"' \
  > /tmp/ghost-mysql-backup.sql
```

2. Stop the job, recreate the host volume directory on the new node, redeploy:
```bash
nomad job stop photo
# provision new host volume directory (run ansible or manually):
# mkdir -p /opt/nomad/volumes/photo-mysql && chown 999:999 /opt/nomad/volumes/photo-mysql
nomad job run jobs/photo-site/photo.hcl
```

3. Restore the dump:
```bash
nomad alloc exec -task database <new-alloc-id> \
  sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD"' < /tmp/ghost-mysql-backup.sql
```
