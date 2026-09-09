# DNS

Two resolvers, one source of truth, three classes of client. This replaces the
single Pi-hole on dionysus (192.168.0.5), which was the acknowledged DNS single
point of failure: roaming tailnet clients could only reach it through hermes's
subnet route, so hermes going down took remote DNS with it.

## Shape

```
                      jobs/*.hcl  Host(`vault.dbyte.xyz`)
                             │  the only place a service name is declared
                             ▼
                    scripts/sync-dns.sh
                     │                 │
        dnsmasq lines│                 │extra-records.json
                     ▼                 ▼
        ┌────────────────────┐   ┌──────────────────┐
        │ Pi-hole × 2        │   │ headscale        │
        │ hermes 192.168.0.4 │   │ worker.cloud     │
        │ zeus   192.168.0.3 │   │                  │
        └────────────────────┘   └──────────────────┘
              ▲        ▲                   ▲
              │        │                   │
       LAN clients  containers      roaming clients
       (DHCP)       (docker0)       (MagicDNS 100.100.100.100)
```

- **LAN clients** get both Pi-holes from DHCP and resolve service names to
  Traefik's LAN address, 192.168.0.4.
- **Containers** on hermes and zeus resolve through 172.17.0.1, which is the
  Docker daemon's configured `dns` and, since the systemd-resolved stub listener
  went away, is answered by that node's own Pi-hole.
- **Roaming clients** ask MagicDNS. Private service names are answered directly
  by headscale from `extra-records.json` at Traefik's *tailnet* address,
  100.64.0.1; everything else forwards to the two Pi-holes over the tailnet.
  Nothing on this path needs the subnet route to be up or approved.

## Source of truth

`scripts/sync-dns.sh` reads every ``Host(`…`)`` rule in `jobs/` (excluding
`jobs/archive/`) and emits two artefacts from that one list:

| Artefact | Consumer | Points at |
|---|---|---|
| `misc.dnsmasq_lines` | both Pi-holes, via the API | `192.168.0.4` (Traefik on the LAN) |
| `extra-records.json` | headscale, via a file it watches | `100.64.0.1` (Traefik on the tailnet) |

`headscale.dbyte.xyz` and `headplane.dbyte.xyz` are excluded from both. They must
resolve to worker's public address everywhere, or a node that has fallen off the
tailnet cannot reach the control plane to rejoin it.

Everything else about the resolvers is config-as-code in
`ansible/group_vars/pihole.yaml`, pushed as forced `FTLCONF_*` settings that the
Pi-hole API and UI show read-only. **The web UI is read-only by convention** —
edit the file and re-run the playbook. The exceptions, and why:

| Not in group_vars | Owner | Why |
|---|---|---|
| `misc.dnsmasq_lines` | `scripts/sync-dns.sh` | derived from `jobs/`, changes on every new service |
| adlists | `ansible/playbooks/pihole.yaml`, via the API | gravity.db, not FTL config |
| allow/deny/group/client rules | one-time Teleporter seed | gravity.db, and hand-curated over years |

## Cutover order (first rollout only)

Run this from a machine on the LAN, not over the tailnet: the middle steps
rewrite `/etc/resolv.conf` and restart the resolver on both nodes, and the last
one changes DNS for every tailnet client.

1. **Secrets.** `vault_pihole_password` into `ansible/group_vars/all.yaml`, and
   the same value into Consul: `consul kv put pihole/password '<value>'`.
2. **`ansible-playbook ansible/playbooks/tailscale.yaml`** — *before* the
   Pi-hole play, not after. It sets `accept_dns: false` on hermes and zeus,
   which is a prerequisite of the next step: with it still true, tailscaled can
   notice `/etc/resolv.conf` is no longer resolved's symlink, switch to direct
   mode, and quietly overwrite what the Pi-hole play wrote. It also makes zeus a
   second subnet router and approves the routes. Note the gap this opens: until
   step 3, `*.ts.dbyte.xyz` does not resolve on those two nodes, so the backup
   heartbeats in `jobs/` fail. Nothing else depends on it.
3. **`ansible-playbook ansible/playbooks/pihole.yaml`** — deploys both
   resolvers, one node at a time. dionysus is still the third entry in each
   node's `resolv.conf`, so the node whose Pi-hole does not exist yet keeps
   resolving throughout.
4. **Teleporter seed** from dionysus into both new instances (command in the
   header of `pihole.yaml`), then **re-run `pihole.yaml`** — the import also
   restores dionysus's FTL settings, and the forced `FTLCONF_*` environment has
   to go back on top.
5. **`ansible-playbook ansible/playbooks/dns.yaml`** — pushes the dnsmasq lines
   to all three Pi-holes and stages `extra-records.json` on worker. Safe to run
   before the control plane reads that file.
6. **Enable it on the control plane.** headplane edits the deployed config in
   place, so the repo copy is not what runs — hand-apply the `dns:` block from
   `external/headscale/config.yaml` to
   `worker.cloud:/opt/headscale/data/config.yaml`, then
   `sudo docker restart headscale`. **This must come after step 3**: it points
   every tailnet client at the two Pi-holes' tailnet addresses, so those have to
   be answering first.
7. **Verify** — the checks below, including the subnet-route failover test.
8. **DHCP** — hand out 192.168.0.4 and 192.168.0.3, keeping 192.168.0.5 third
   for the soak.
9. **`nomad job run jobs/pihole-backup.hcl`** — the updated job backs up the new
   pair rather than dionysus.

## Applying a change

Adding a service with a new `Host()` rule:

```sh
ansible-playbook ansible/playbooks/dns.yaml
```

That regenerates both artefacts, PATCHes `misc.dnsmasq_lines` on each Pi-hole in
turn, and replaces `extra-records.json` on worker by rename (headscale watches it
with fsnotify; a partial in-place write is a parse error — headscale issue
\#2753).

The untracked `.git/hooks/post-commit` runs `scripts/sync-dns.sh --apply` on any
commit touching `jobs/`, which covers the Pi-hole half only. **The headscale half
needs the playbook.** If the hook is ever moved or the script renamed again, the
hook must be updated by hand — it is machine-local and not in the repo.

Changing resolver config (upstreams, static records, adlists, the password):

```sh
ansible-playbook ansible/playbooks/pihole.yaml
```

It runs one node at a time. That `serial: 1` is not a nicety — a rollout that
took both resolvers down together would take the LAN, the tailnet and every
container's DNS with it.

## Why host networking and not macvlan

macvlan is the obvious alternative and it solves the ugliest part of this
design: give the container its own LAN address and there is no contest for
:53 at all, so systemd-resolved's stub listener could stay, `/etc/resolv.conf`
could stay a symlink, and the `server=/consul/` forwarder would be unnecessary.

It was still rejected, for one decisive reason and one practical one:

- **A macvlan container has no tailnet address.** The entire point of this phase
  is that headscale's `nameservers.global` are the resolvers' *tailnet*
  addresses, so a roaming client gets DNS over a direct peer path instead of
  through hermes's subnet route. A LAN-only resolver puts that dependency
  straight back, which is the single point of failure being removed. The
  workaround — running tailscale inside each Pi-hole container — means two more
  tailnet nodes to register, key, and keep alive.
- **A macvlan host cannot reach its own macvlan container.** hermes could not
  use the resolver running on hermes without an extra shim interface and route,
  and the Docker daemon's `dns: 172.17.0.1` arrangement would need reworking
  too.

Host networking gives the resolver the LAN address, the tailnet address and
docker0 from one listener, which is exactly the set of clients it has to serve.
The cost is the stub-listener surgery below.

## Why systemd-resolved's stub listener is off

FTL listens on the wildcard address, which cannot coexist with resolved's stub
on 127.0.0.53 or its `DNSStubListenerExtra` on 172.17.0.1. So on hermes and zeus:

- `/etc/systemd/resolved.conf.d/pihole.conf` sets `DNSStubListener=no` and the
  old `docker.conf` drop-in is removed,
- `/etc/resolv.conf` stops being a symlink into `/run/systemd/resolve` and
  becomes a real file listing the peer's Pi-hole, this node's own, and dionysus
  during the soak,
- `.consul` keeps resolving because `sync-dns.sh` emits
  `server=/consul/127.0.0.1#8600` and the Pi-hole container uses host
  networking, so that loopback is the host's own Consul agent.

The peer's resolver is listed **first** deliberately: it keeps the cross-node
path exercised on every lookup, so a broken peer surfaces immediately instead of
lying dormant until this node's own resolver fails. The cost is a one-second
penalty per lookup while the peer is down, which is why the retry budget in
`resolv.conf` is `timeout:1 attempts:2`. Swapping the order is a one-line change
in `templates/pihole/resolv.conf.j2` if that trade stops being worth it.

## Why these nodes do not accept tailnet DNS

`tailscale_accept_dns` is `false` on hermes and zeus, as it already was on
worker. A node whose own resolution is served by MagicDNS, whose upstream is that
same node's Pi-hole, is a loop; and tailscaled would fight the static
`/etc/resolv.conf` the playbook writes.

The cost is that `*.ts.dbyte.xyz` no longer resolves on these nodes by default,
and jobs *do* use it — the backup heartbeats target
`observability.ts.dbyte.xyz`. Two things cover that:

- static records for every inventory host's MagicDNS name, generated into
  `FTLCONF_dns_hosts` from the `tailnet_ipv4` host_vars, and
- `server=/ts.dbyte.xyz/100.100.100.100` in the dnsmasq lines, so any *other*
  tailnet name still forwards to the local tailscaled.

`tailnet_ipv4` in `ansible/host_vars/*.yaml` is the single source of truth for
tailnet addressing and is reused by the cluster work in a later phase.

## Port 53 is the one thing firewalled

The home nodes deliberately run no general host firewall: `INPUT` policy is
`ACCEPT` and there is no public IPv4. Port 53 is the exception, applied by
`/opt/pihole/dns-firewall.sh` via a systemd unit ordered after Docker and
tailscaled (both rewrite `INPUT` when they start).

It exists because the home line is DS-Lite: br0 carries a globally routable IPv6
address, and FTL listens on the wildcard. Without those rules the resolver would
be an open resolver on the public internet the moment the router's inbound
policy changed. Accepted sources are loopback, 192.168.0.0/24, 100.64.0.0/10,
172.16.0.0/12 (docker0 and any Nomad bridge) on v4; loopback, link-local and
`fc00::/7` on v6. Everything else asking on :53 is dropped.

## Verifying

```sh
# Both resolvers answer for a private name, from the LAN
dig +short vault.dbyte.xyz @192.168.0.4
dig +short vault.dbyte.xyz @192.168.0.3

# Roaming: answered by headscale's extra_records, no subnet route involved
tailscale dns query vault.dbyte.xyz

# Ad-blocking is live on both
dig +short doubleclick.net @192.168.0.4     # expect 0.0.0.0
dig +short doubleclick.net @192.168.0.3

# .consul still resolves through the Pi-hole forwarder
dig +short traefik-http.service.consul @192.168.0.4

# Subnet-route failover — run this from the LAN, never over the tailnet
ssh distro@192.168.0.4 'sudo systemctl stop tailscaled'
#   a roaming client should still resolve, and reach 192.168.0.5, via zeus
#   within ~15-30s
ssh distro@192.168.0.4 'sudo systemctl start tailscaled'
```

## Upstream recursion depends on IPv6

The upstream list in `group_vars/pihole.yaml` puts IPv6 resolvers first, and
that ordering is not a preference. The line is DS-Lite with the IPv4-in-IPv6
tunnel disabled by the ISP, so IPv6 is the only native transit out of the
house; the IPv4 upstreams are reachable only through the tailscale exit node,
which needs the tailnet, which needs headscale over IPv6.

So the v4 upstreams are a degraded path, not an independent fallback. If IPv6
recursion breaks, they break with it. **Treat "no IPv6 at home" as "no DNS at
home"** and repair it at the router — the failure this actually caused on
2026-09-08 was the router being switched to stateful DHCPv6, which stopped
SLAAC producing addresses on hosts that run no DHCPv6 client. See
docs/Headscale.md for the check.

The same applies to dionysus while it is still serving: its recursion runs
entirely on its IPv6 upstreams.

## Rollback: undoing the resolver surgery on one node

`pihole.yaml` changes three things that a failed FTL start leaves in a bad
state, and `docker compose down` alone does not undo any of them. To put a node
back the way it was, in this order:

```sh
# 1. Give systemd-resolved its stub listener back, including the docker0 extra
#    that the Docker daemon's `dns: 172.17.0.1` depends on, and the consul
#    routing the Pi-hole forwarder was doing in its place.
sudo rm -f /etc/systemd/resolved.conf.d/pihole.conf
sudo tee /etc/systemd/resolved.conf.d/docker.conf >/dev/null <<'EOF'
[Resolve]
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF
sudo tee /etc/systemd/resolved.conf.d/consul.conf >/dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
Domains=~consul node.consul service.consul
EOF

# 2. Stop FTL so :53 is free for the stub listener.
sudo docker compose -f /opt/pihole/docker-compose.yml down

# 3. Restore resolv.conf as the symlink resolved manages.
sudo rm -f /etc/resolv.conf
sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

# 4. Drop the port-53 rules. The script only adds them, so remove by hand.
sudo systemctl disable --now pihole-dns-firewall.service
sudo iptables-save  | grep -F -- '--comment pihole-dns' | sed 's/^-A /-D /' \
  | while read -r r; do sudo iptables  $r; done
sudo ip6tables-save | grep -F -- '--comment pihole-dns' | sed 's/^-A /-D /' \
  | while read -r r; do sudo ip6tables $r; done

# 5. Confirm.
resolvectl status | grep -A2 '^Global'
dig +short vault.dbyte.xyz
sudo docker run --rm alpine getent hosts deb.debian.org
```

Step 4 last, and step 1 first, is deliberate: while the DROP is in place and no
resolver is listening, the node has no DNS at all except its `resolv.conf`
fallbacks. Note that the container check in step 5 is the one people forget —
the docker0 stub listener is what every Nomad task resolves through.

## Break-glass: both resolvers unreachable

`dns.nameservers.global` is deliberately the two Pi-holes and nothing else, so
every lookup goes through the blocker. The price is that if both home nodes are
down, a roaming client has no DNS at all — not even for public names, because
MagicDNS is a `~.` catch-all on the client. This happened on 2026-09-08 with the
old single-resolver setup and would happen again with the pair.

Fastest fix, on the affected client, no control-plane change:

```sh
sudo tailscale set --accept-dns=false
```

The OS falls back to its own resolvers (DHCP or whatever the network hands out)
immediately. Private names stop resolving, public ones work. Undo with
`--accept-dns=true` once home is back.

If it needs fixing for every client at once, add a public resolver to the
control plane. Note that `headscale.dbyte.xyz` may not resolve while this is
happening — use worker's address directly:

```sh
ssh ubuntu@141.147.74.4
sudo vi /opt/headscale/data/config.yaml     # add "- 9.9.9.9" under dns.nameservers.global
sudo docker restart headscale
```

Clients pick up the new netmap within seconds. **Revert it once home is back**:
the fallback bypasses ad-blocking, and while it is in place a private name that
is not in `extra-records.json` (anything `.internal` or `.consul`) can get a
public answer instead of failing.

## Retiring dionysus

The old Pi-hole stays as a tertiary resolver through the soak. When the pair has
been trusted for a week or two:

1. Remove 192.168.0.5 from DHCP's DNS list, leaving .4 and .3.
2. Empty `pihole_fallback_resolvers` in `ansible/group_vars/pihole.yaml` and
   re-run `ansible/playbooks/pihole.yaml`.
3. Leave `192.168.0.5 dionysus.internal` in `pihole_static_hosts` — the NAS keeps
   that name for NFS and the backup jobs.
4. Stop the Pi-hole package on the Synology.

`jobs/pihole-backup.hcl` already backs up the new pair and not dionysus.
