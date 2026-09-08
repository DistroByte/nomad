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

### Nodes must resolve headscale independently

hermes and zeus carry static entries so tailscaled can find the control plane
regardless of resolver state. Add them to any new node.

```
# /etc/hosts
2603:c020:c014:4eff::10  headscale.dbyte.xyz
2603:c020:c014:4eff::10  headplane.dbyte.xyz
```

This is not about MagicDNS being circular — LAN nodes reach the Pi-hole
directly over `br0`, so they resolve fine with the tailnet down. It guards
against the duller failure that actually bit twice: a record that has not
propagated, or a negative cache pinning the node to a dead address family.
On 2026-09-07 Pi-hole held a NODATA for the new AAAA for the full 1800s SOA
minimum, so every LAN node kept trying IPv4 that no longer existed.

The separate, real SPOF is `dns.nameservers.global` in
`external/headscale/config.yaml` — a single LAN address that **remote** clients
can only reach via hermes's subnet route. When that route stopped serving, DNS
died for every roaming client and the Gatus `internal` group went blind. Split
DNS is the fix; hosts entries do not address it.

**Never restart `tailscaled` over a connection routed through the tailnet.** The
restart severs the session issuing it, and if the node cannot re-register there
is no second way in — the home router firewalls inbound IPv6 and there is no
inbound IPv4. Do it from the LAN.

### IPv6

Dual-stack since 2026-09-07, in `2603:c020:c014:4eff::/64` of the VCN's
Oracle-allocated `/56`:

| Host          | IPv4             | IPv6                      |
| ------------- | ---------------- | ------------------------- |
| worker        | 141.147.74.4     | `2603:c020:c014:4eff::10` |
| observability | 132.226.210.138  | `2603:c020:c014:4eff::11` |

`headscale.dbyte.xyz` has both A and AAAA, which is what lets nodes on
IPv4-degraded links reach the control plane at all.

It also removed a DERP hop — hermes (v6-only) and observability (v4-only) had
no address family in common and relayed every packet. They now peer directly at
`[2603:c020:c014:4eff::11]:41641`, 14ms.

OCI security lists permit everything from `0.0.0.0/0` and `::/0`, so host
`iptables`/`ip6tables` rules are the only filtering here. The v6 chains were
empty until written by hand; anything bound to `[::]` is exposed unless a rule
says otherwise.

## Initial Rollout

The control plane is a Docker Compose stack on `worker` (141.147.74.4), so all
headscale CLI calls go over SSH into that container. `--config` is not optional:
without it the CLI logs `no config file found, using defaults` and operates
against default paths rather than the real database.

```bash
# 1. Deploy headscale (Caddy + headscale + headplane)
ansible-playbook -i ansible/hosts ansible/playbooks/headscale.yaml

# 2. Create a user
ssh ubuntu@141.147.74.4 'sudo docker exec headscale headscale \
  --config /var/lib/headscale/config.yaml users create distro'

# 3. Create a reusable pre-auth key
ssh ubuntu@141.147.74.4 'sudo docker exec headscale headscale \
  --config /var/lib/headscale/config.yaml preauthkeys create \
  --user 1 --reusable --expiration 90d'

# 4. Store the key in Ansible vault
ansible-vault encrypt_string '<key>' --name vault_tailscale_authkey \
  >> ansible/group_vars/all.yaml

# 5. Install Tailscale on homelab nodes
ansible-playbook -i ansible/hosts ansible/playbooks/tailscale.yaml

# 6. Approve routes for each node (see below)
```

## Approving Routes for a Node

After a node connects, its advertised routes must be approved server-side. Routes persist in the SQLite database.

Nothing automates this. No playbook approves routes, and `tailscale_args` in
`ansible/group_vars/tailscale.yaml` carries `--reset`, so a re-register can
leave a route advertised but unapproved.

```bash
# List what a node is advertising
ssh ubuntu@141.147.74.4 'sudo docker exec headscale headscale \
  --config /var/lib/headscale/config.yaml nodes list-routes --identifier <id>'

# Approve subnet route + exit node routes (IPv4 and IPv6)
ssh ubuntu@141.147.74.4 'sudo docker exec headscale headscale \
  --config /var/lib/headscale/config.yaml nodes approve-routes \
  --identifier <id> \
  --routes 192.168.0.0/24,0.0.0.0/0,::/0'
```

`approve-routes` sets the **full** approved list rather than adding to it — pass
every route the node should serve, or the omitted ones are revoked. Approving
just `192.168.0.0/24` on hermes would silently drop its exit node.

Read the output columns carefully. `Available` is what the node advertises;
`Approved` is what you have allowed; `Serving (Primary)` is what is actually
carrying traffic. A route in `Available` but absent from `Approved` is inert:

```
ID | Hostname | Approved        | Available                       | Serving (Primary)
1  | hermes   | 0.0.0.0/0, ::/0 | 0.0.0.0/0, ::/0, 192.168.0.0/24 | 0.0.0.0/0, ::/0
```

That state breaks every tailnet client's DNS, because `dns.nameservers.global`
in `external/headscale/config.yaml` is `192.168.0.5` — an address only reachable
*through* that subnet route. It also blinds the Gatus `internal` check group,
which reaches 192.168.0.0/24 the same way, so the failure does not alert.

For a node that is only a subnet router (not an exit node), omit `0.0.0.0/0` and `::/0`.

## Workstations are not Ansible-managed

`archdesktop` and `archlaptop` are not in the `[tailscale]` group in
`ansible/hosts` — only the four servers (`hermes`, `zeus`,
`observability.cloud`, `worker.cloud`) are. That means they never get the
composed `tailscale_args` from `ansible/group_vars/tailscale.yaml`, and every
manual `tailscale up` on them is easy to get wrong in a way that silently
resets state rather than erroring:

**If you ever run `tailscale up` without `--login-server`, tailscale switches
back to the default coordination server and treats it as a new login.** That
also drops `--operator` and `--accept-routes` on the resulting profile, even
though those look like independent, persisted settings — they are, but only
*within* a given login-server's profile. This is why re-running `tailscale up`
on a workstation with a partial flag set looks like "settings won't stick":
the profile itself got swapped out from under it, not the individual flags.

Two ways to fix a workstation properly, instead of hand-typing flags each time:

1. **Add it to Ansible** (`tailscale_operator` was added to
   `group_vars/tailscale.yaml` for exactly this case). Add the host to
   `[tailscale]` in `ansible/hosts`, set `tailscale_operator` in its
   `host_vars`, and let `ansible/playbooks/tailscale.yaml` apply the same
   composed `tailscale_args` the servers get — including the reusable
   pre-auth key from vault. Consistent with everything else in this doc, but
   requires the workstation to be SSH-reachable and pushed to like a server.
2. **A local systemd oneshot unit** running the full flag set on boot, for a
   box you don't want Ansible touching:
   ```sh
   #!/bin/sh
   exec tailscale up \
     --login-server=https://headscale.dbyte.xyz \
     --operator=james \
     --accept-routes \
     --authkey=file:/etc/tailscale/authkey
   ```
   `systemctl enable` a oneshot unit with `After=tailscaled.service` that runs
   this script. The auth key must be a **reusable** pre-auth key (see
   `preauthkeys create --reusable` above) — a single-use key only works once,
   and a workstation that keeps losing its control-plane connection needs to
   be able to re-register without you generating a new key each time.

Neither path is done for `archdesktop`/`archlaptop` yet — this section
documents the gap, not a fix already applied.

## Useful Commands

Define this once per shell so the commands below stay readable:

```bash
hs() {
  ssh ubuntu@141.147.74.4 \
    "sudo docker exec headscale headscale --config /var/lib/headscale/config.yaml $*"
}
```

```bash
# List all nodes
hs nodes list

# List routes across all nodes
hs nodes list-routes

# Expire (force re-auth) a node
hs nodes expire --identifier <id>

# Delete a node
hs nodes delete --identifier <id>

# List pre-auth keys (flag name varies by headscale version — check --help)
hs preauthkeys list

# Create a new pre-auth key
hs preauthkeys create --user 1 --reusable --expiration 90d
```

`Connected: offline` in `nodes list` means the node has lost its **control**
connection, not that it is unreachable. A node can show offline while still
passing traffic over an established DERP path — during the September 2026
outage hermes was `offline` for 26 hours while Traefik on it kept serving every
public site through the relay. Confirm the data path separately before
concluding a node is down:

```bash
ssh ubuntu@132.226.210.138 'tailscale ping -c 2 100.64.0.1'
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
