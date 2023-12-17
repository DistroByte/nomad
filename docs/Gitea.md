---
tags:
  - services
  - infrastructure
---
[Gitea](https://git.dbyte.xyz) is a self hosted git server, much like GitHub or GitLab, that I use as my code hosting server. It has the capabilities to store packages (like container images), host CI/CD, and has project management features. It is also very lightweight.

Gitea is deployed and configured with the [gitea](../jobs/gitea.hcl) job alongside a [PostgreSQL](PostgreSQL.md) database.

## Backups

The data stored in Gitea is written directly to an NFS share on [Synology DS920+](Synology%20DS920+.md), and the configuration in the [PostgreSQL](PostgreSQL.md) database is backed up according to the [postgresql-backup](../jobs/postgresql/postgresql-backup.hcl) job.
