---
title: Headscale / Tailscale
tags: [services, networking, vpn]
---

# Headscale / Tailscale

Self-hosted Tailscale coordination server. Provides a WireGuard mesh between homelab nodes, phone, and laptop. Headscale only handles the control plane (key exchange, identity) — actual traffic flows peer-to-peer over WireGuard, not through headscale.

## Architecture

- **Headscale** runs as a Nomad job on hermes, exposed via Traefik at `https://headscale.dbyte.xyz`. State (SQLite, private keys) lives on a Synology CSI volume.
- **Tailscale** runs as a systemd service directly on hermes (not in a container — it needs kernel-level WireGuard interfaces). Managed by the `ansible/playbooks/tailscale.yaml` playbook.
- **hermes** advertises `192.168.0.0/24` as a subnet route and is configured as an exit node. All devices can reach LAN addresses through it.
- **MagicDNS** resolves nodes as `<hostname>.ts.dbyte.xyz`.

Headscale going down does not kill existing WireGuard sessions. Sessions only break when node keys need rotating (default: 180 days). New device registration requires headscale to be reachable.

## Initial Rollout

```bash
# 1. Provision the CSI volume
nomad volume create jobs/headscale/headscale-data.csi.hcl

# 2. Deploy headscale
nomad job run jobs/headscale/headscale.hcl

# 3. Create a user
nomad alloc exec -job headscale headscale users create distro

# 4. Create a reusable pre-auth key
nomad alloc exec -job headscale headscale preauthkeys create \
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
nomad alloc exec -job headscale headscale nodes list-routes --identifier <id>

# Approve subnet route + exit node routes (IPv4 and IPv6)
nomad alloc exec -job headscale headscale nodes approve-routes \
  --identifier <id> \
  --routes 192.168.0.0/24,0.0.0.0/0,::/0
```

For a node that is only a subnet router (not an exit node), omit `0.0.0.0/0` and `::/0`.

## Adding a New Exit Node (Another Region)

1. Provision a VPS, add it to the inventory:

```ini
# ansible/hosts
[tailscale]
hermes tailscale_advertise_routes="192.168.0.0/24" tailscale_exit_node=true
us-east ansible_host=1.2.3.4 ansible_user=debian
```

2. Create its host vars:

```yaml
# ansible/host_vars/us-east.yaml
tailscale_exit_node: true
```

3. Run the playbook against it:

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/tailscale.yaml --limit us-east
```

4. Register it with headscale. If using interactive auth:

```bash
nomad alloc exec -job headscale headscale nodes register --user 1 --key <nodekey>
```

5. Approve its exit node routes:

```bash
nomad alloc exec -job headscale headscale nodes list-routes --identifier <id>
nomad alloc exec -job headscale headscale nodes approve-routes \
  --identifier <id> \
  --routes 0.0.0.0/0,::/0
```

The new node now appears in the Tailscale app as a selectable exit node alongside hermes.

## Registering a Client Device (Phone / Laptop)

Install Tailscale, point it at `https://headscale.dbyte.xyz` as the control server. Either:

- **Pre-auth key**: use the key generated above — no server-side approval needed.
- **Interactive**: headscale will print a registration command to run:

```bash
nomad alloc exec -job headscale headscale nodes register --user 1 --key <nodekey-from-device>
```

## Useful Commands

```bash
# List all nodes
nomad alloc exec -job headscale headscale nodes list

# Expire (force re-auth) a node
nomad alloc exec -job headscale headscale nodes expire --identifier <id>

# Delete a node
nomad alloc exec -job headscale headscale nodes delete --identifier <id>

# List pre-auth keys
nomad alloc exec -job headscale headscale preauthkeys list --user 1

# Create a new pre-auth key
nomad alloc exec -job headscale headscale preauthkeys create \
  --user 1 --reusable --expiration 90d
```
