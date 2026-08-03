---
title: Vaultwarden
tags: [services, infrastructure]
---

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is an unofficial Bitwarden compatible server written in Rust. It has many capabilities that mimic [Bitwarden](https://bitwarden.com/) premium.

Vaultwarden is deployed and configured with the [vaultwarden](../jobs/vaultwarden/vaultwarden.hcl) job. Its data lives on the `vaultwarden` Synology CSI volume, and its secrets (admin token, SMTP, Yubico) are pulled from Consul KV.

## Backups

Vaultwarden's `/data` sits on the `vaultwarden` CSI volume, backed by NFS on the [Synology DS920+](Synology%20DS920+.md). There is no application-level backup job — durability relies on the Synology volume itself.

## Security Concerns

Fail2ban is used to prevent brute forcing passwords. See [this guide](https://github.com/dani-garcia/vaultwarden/wiki/Fail2Ban-Setup) for more.
