# Disaster Recovery

How to rebuild from offsite state, in dependency order. The design goal: every
step here must work with the home LAN, the Nomad cluster, and the tailnet all
dead.

## The circular dependency, and its escape hatch

The Ansible vault password lives in Bitwarden — which is Vaultwarden, hosted on
the cluster. Restoring Vaultwarden needs Ansible, which needs the vault
password, which is in Vaultwarden. The circle is broken by an **offline copy**
(paper, or an age-encrypted file kept off this infrastructure) of exactly
these secrets:

1. Ansible vault password (Bitwarden item "Nomad Ansible Vault Key")
2. `restic` repository password for the homelab repo (`restic/password` in Consul KV)
3. `restic` repository password for the headscale repo (`vault_headscale_restic_password`)
4. Backblaze B2 key id + application key
5. Bitwarden **master password** (nothing restores your ability to read the vault if this is gone)

Keep the copy current: when any of these rotate, rotate the offline copy the
same day.

## What is backed up, where

| Data | Produced by | Lands in | Shipped offsite by |
|---|---|---|---|
| Headscale db.sqlite + noise key + config | systemd timer on worker (`headscale-backup.timer`) | B2 `<bucket>/headscale` | itself (direct, never via tailnet) |
| Vaultwarden sqlite + attachments/keys | `backup` task in `jobs/vaultwarden/vaultwarden.hcl` | `/backups/vaultwarden` | `jobs/backup/restic-offsite.hcl` |
| Paperless full export | `exporter` task in `jobs/paperless/paperless.hcl` | `/backups/paperless` | restic-offsite |
| Immich Postgres dumps | `jobs/immich/immich-backup.hcl` (03:00) | CSI `immich-postgres-backup` | restic-offsite |
| Ghost/photo MySQL dumps | `jobs/photo-site/photo-backup.hcl` (04:00) | CSI `photo-mysql-backup` | restic-offsite |
| Pi-hole Teleporter export | `jobs/pihole-backup.hcl` (04:00) | `/backups/pihole` | restic-offsite |
| Home Assistant / z2m backups | the apps themselves | `/backups/{home-assistant,zigbee2mqtt}` | restic-offsite |

`restic-offsite` runs at 05:00 and ships everything above (plus anything else
under `/backups`) to B2. Every producer POSTs a Gatus heartbeat on success —
group `backups` on the external monitor; a silent day pages via ntfy.

## Restore order

1. **Headscale first** — nothing else is reachable remotely without the tailnet.
   On a fresh VM (or the rebuilt worker):

   ```sh
   export RESTIC_REPOSITORY='s3:https://s3.<region>.backblazeb2.com/<bucket>/headscale'
   export RESTIC_PASSWORD='<from the offline copy>'
   export AWS_ACCESS_KEY_ID='<b2 key id>' AWS_SECRET_ACCESS_KEY='<b2 app key>'
   restic restore latest --target /tmp/hs-restore
   mkdir -p /opt/headscale/data
   cp /tmp/hs-restore/**/db.sqlite /tmp/hs-restore/**/noise_private.key \
      /tmp/hs-restore/**/config.yaml /opt/headscale/data/
   ```

   Point public DNS `headscale.dbyte.xyz` + `headplane.dbyte.xyz` at the host,
   then run `ansible-playbook -i ansible/hosts ansible/playbooks/headscale.yaml`.
   Nodes reconnect on their own — the noise key and DB are their identity.

2. **Tailnet nodes** come back as headscale returns; verify with
   `headscale nodes list` (alias `hs` on worker).

3. **Vaultwarden** — restore the newest dump onto the volume:

   ```sh
   restic restore latest --target /tmp/lab-restore --include '/data/backups/vaultwarden'
   # newest db.<stamp>.sqlite3 is a ready-to-use database file:
   cp '/tmp/lab-restore/.../db.<stamp>.sqlite3' <vaultwarden volume>/db.sqlite3
   tar xzf '/tmp/lab-restore/.../files.<stamp>.tar.gz' -C <vaultwarden volume>/
   ```

   Once Vaultwarden serves again, `ansible/vault-password.sh` works and the
   rest of the estate can be driven by Ansible + Nomad normally.

4. **Databases** — Immich: `gunzip -c backup.<stamp>.sql.gz | psql -U <user>`
   against a fresh primary before starting the server task. Photo MySQL: same
   shape with `mysql`. Paperless: `document_importer` against the restored
   export directory.

## Rules that keep this recoverable

- Never restart `tailscaled` over a tailnet-routed connection (docs/Headscale.md).
- The headscale backup never touches the tailnet or Consul KV; its secrets live
  only in `/etc/headscale-backup.env` on worker and in ansible-vault.
- Test a restore (at minimum: `restic restore latest` of the vaultwarden dump
  and the headscale db to a scratch directory) after first setup, then
  quarterly.
