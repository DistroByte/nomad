---
tags:
  - services
---
# Vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is an unofficial Bitwarden compatible server written in Rust. It has many capabilities that mimic [Bitwarden](https://bitwarden.com/) premium.

Vaultwarden is deployed and configured with the [vaultwarden](../jobs/vaultwarden.hcl) job alongside a [PostgreSQL](PostgreSQL.md) database.

## Backups

The data stored in Vaultwarden is stored on my NFS share on [Synology DS920+](Synology%20DS920+.md), and the configuration in the [PostgreSQL](PostgreSQL.md) database is backed up according to the [postgresql-backup](../jobs/postgresql/postgresql-backup.hcl) job.

## Security Concerns

Fail2ban is used to prevent brute forcing passwords. See [this guide](https://github.com/dani-garcia/vaultwarden/wiki/Fail2Ban-Setup) for more.

## Quirks

[[Traefik]] must proxy requests to `https`, not `http` like it does by default.