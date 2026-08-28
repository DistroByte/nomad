---
title: Headscale / Tailscale
tags: [services, networking, vpn]
---

# Headscale / Tailscale

Self-hosted Tailscale coordination server. Provides a WireGuard mesh between homelab nodes, phone, and laptop. Headscale only handles the control plane (key exchange, identity) — actual traffic flows peer-to-peer over WireGuard, not through headscale.

## Architecture

- **Headscale** runs off-cluster on `worker` (Oracle, London) as a Docker Compose stack, with Caddy terminating TLS for `headscale.dbyte.xyz` and `headplane.dbyte.xyz`. Deployed by `ansible/playbooks/headscale.yaml`; state lives in `/opt/headscale/data`.
- **Tailscale** runs as a systemd service directly on hermes (not in a container — it needs kernel-level WireGuard interfaces). Managed by the `ansible/playbooks/tailscale.yaml` playbook.
- **hermes** advertises `192.168.0.0/24` as a subnet route and is configured as an exit node. All devices can reach LAN addresses through it.
- **MagicDNS** resolves nodes as `<hostname>.ts.dbyte.xyz`.

### Why the control plane is off-cluster

It used to run as a Nomad job on hermes behind Traefik. When the home line moved
to Virgin fibre it landed on DS-Lite with no public IPv4, so
`headscale.dbyte.xyz` resolved to the carrier's AFTR and refused connections.
Every node lost its netmap and there was no way to re-register any of them,
because fixing it needed the tailnet that headscale provides.

Running it on a host with a real public address breaks that loop: nodes reach
the control plane outbound over the open internet, so the tailnet is always
recoverable from cold. This is also why it is not a Nomad job — scheduling the
control plane on infrastructure that needs the control plane is the same
deadlock with more steps.

### Failure behaviour

Losing headscale does not immediately drop established **direct** peer
connections, but it is not benign. Peers relaying through DERP degrade within
minutes once the netmap stops refreshing, and observed behaviour during the
August 2026 outage was total loss between hermes and the cloud nodes while both
still reported their peers as `active`. Treat headscale being unreachable as an
outage, not an inconvenience.

Node keys themselves do not expire by default here — `headscale nodes list`
shows `Expiration: N/A`. Nodes that go offline reconnect with their existing
identity once the control plane returns, provided the SQLite database and
`noise_private.key` survive.

## Initial Rollout

```bash
# 1. Provision the CSI volume
nomad volume create jobs/headscale/headscale-data.csi.hcl

# 2. Deploy headscale
nomad job run jobs/headscale/headscale.hcl

# 3. Create a user
nomad alloc exec -task headscale -job headscale headscale users create distro

# 4. Create a reusable pre-auth key
nomad alloc exec -task headscale -job headscale headscale preauthkeys create \
  --user 1 --reusable --expiration 90d

# 5. Store the key in Ansible vault
ansible-vault encrypt_string '<key>' --name vault_tailscale_authkey \
  >> ansible/group_vars/all.yaml

# 6. Install Tailscale on homelab nodes
ansible-playbook -i ansible/hosts ansible/playbooks/tailscale.yaml

# 7. Approve routes for each node (see below)
```

## Approving Routes for a Node

After a node connects, its advertised routes must be approved server-side. Routes persist in the SQLite database.

```bash
# List what a node is advertising
nomad alloc exec -task headscale -job headscale headscale nodes list-routes --identifier <id>

# Approve subnet route + exit node routes (IPv4 and IPv6)
nomad alloc exec -task headscale -job headscale headscale nodes approve-routes \
  --identifier <id> \
  --routes 192.168.0.0/24,0.0.0.0/0,::/0
```

For a node that is only a subnet router (not an exit node), omit `0.0.0.0/0` and `::/0`.

## Useful Commands

```bash
# List all nodes
nomad alloc exec -task headscale -job headscale headscale nodes list

# Expire (force re-auth) a node
nomad alloc exec -task headscale -job headscale headscale nodes expire --identifier <id>

# Delete a node
nomad alloc exec -task headscale -job headscale headscale nodes delete --identifier <id>

# List pre-auth keys (flag name varies by headscale version — check --help)
nomad alloc exec -task headscale -job headscale headscale preauthkeys list

# Create a new pre-auth key
nomad alloc exec -task headscale -job headscale headscale preauthkeys create \
  --user 1 --reusable --expiration 90d
```

## Migrating state to the off-cluster control plane

`db.sqlite` holds every node's identity and `noise_private.key` is the server's
identity. Lose either and all nodes are orphaned and must re-register by hand.
The playbook refuses to start the stack if they are absent.

```bash
# 1. Stop the old control plane. The CSI volume is single-node-writer, so the
#    export job will not place while headscale still holds it.
nomad job stop headscale

# 2. Export state to the NFS backup share.
nomad job run jobs/headscale/headscale-export.hcl
nomad alloc logs -job headscale-export

# 3. Move it to the new host and unpack.
scp /backups/headscale/headscale-state.tar.gz ubuntu@141.147.74.4:/tmp/
ssh ubuntu@141.147.74.4 \
  'sudo mkdir -p /opt/headscale/data && sudo tar xzf /tmp/headscale-state.tar.gz -C /opt/headscale/data'

# 4. Point both hostnames at the new host BEFORE deploying — Caddy issues
#    certificates over HTTP-01 and will fail if DNS still points home.
#      headscale.dbyte.xyz  A  141.147.74.4
#      headplane.dbyte.xyz  A  141.147.74.4

# 5. Deploy.
ansible-playbook -i ansible/hosts ansible/playbooks/headscale.yaml

# 6. Confirm, then watch the nodes come back on their own.
curl -sI https://headscale.dbyte.xyz/health
ssh ubuntu@141.147.74.4 \
  'sudo docker exec headscale headscale nodes list --config /var/lib/headscale/config.yaml'
```

Both hostnames stay excluded from `scripts/sync-pihole-dns.sh` — they must
resolve to the public address everywhere, including on the LAN, or a node on the
home network would try to reach the control plane over the tailnet it is trying
to join.

Once nodes are back, remove the old job spec's CSI volume only after confirming
the new deployment is healthy; it is the only copy of the pre-migration state.
