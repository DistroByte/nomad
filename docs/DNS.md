# DNS

One resolver, one recursion path. The redundant Pi-hole pair that used to run on
hermes and zeus was decommissioned on 2026-09-14; this document describes what
replaced it and, at the end, why.

## Shape

```
LAN client ──DHCP──> 192.168.0.5 (dionysus, Pi-hole) ──> 9.9.9.9 / 1.1.1.1
                            ^
roaming client ──MagicDNS──┘  (via hermes' 192.168.0.0/24 subnet route)

hermes / zeus                 container on those nodes
  getaddrinfo                   resolv.conf -> 172.17.0.1
    -> nss-resolve                              |
    -> systemd-resolved (stub 127.0.0.53)  <----+  DNSStubListenerExtra
         -> 127.0.0.1:8600 (local Consul agent)
              -> .consul answered locally
              -> everything else via Consul's recursors
```

Two separate things resolve names here, and conflating them is the main way to
get confused:

- **dionysus** serves the LAN and, through MagicDNS, roaming clients. It is the
  ad-blocker and the only place blocklists exist.
- **The Nomad nodes** do not use dionysus at all. They resolve through their
  local Consul agent, which answers `.consul` itself and recurses for the rest.
  This is why a node keeps resolving even when dionysus is down, and why
  ad-blocking does not apply to anything running on the cluster.

## Node resolution: the nsswitch trap

`/etc/nsswitch.conf` on both nodes reads:

```
hosts: files resolve [!UNAVAIL=return] dns myhostname
```

`resolve` is nss-resolve, which asks systemd-resolved over D-Bus. The
`[!UNAVAIL=return]` action means *stop on any status except UNAVAIL* — so if
resolved is running but answers NOTFOUND, glibc returns failure immediately and
never falls through to `dns`, which is the entry that would read
`/etc/resolv.conf`.

This bit hard on 2026-09-13. The Pi-hole playbook disabled resolved's stub
listener and wrote a static `resolv.conf`, but left resolved running with no
upstreams. Every `getaddrinfo` failed while `dig` — which bypasses NSS entirely
and reads `resolv.conf` directly — kept working perfectly. The Docker daemon
uses glibc, so image pulls failed, the CSI plugins never registered, and jobs
with volume constraints sat queued for two days.

If host resolution looks broken but `dig` is fine, check this first:

```sh
getent -s dns  hosts example.com   # reads resolv.conf — should work
getent -s resolve hosts example.com   # asks resolved — the one that lies
resolvectl status | grep -A3 '^Global'   # must list a real upstream
```

The invariant: **resolved must always have a working upstream**, because nss
short-circuits on its answer. Today that upstream is the Consul agent, set in
`/etc/systemd/resolved.conf.d/consul.conf`.

## Containers

The Docker daemon is configured with `"dns": ["172.17.0.1"]`, and resolved
listens there via `DNSStubListenerExtra` in
`/etc/systemd/resolved.conf.d/docker.conf`. Every Nomad task resolves through
that address, so it is the half most worth checking after any resolver change
and the half most easily forgotten — the host keeps working when it breaks:

```sh
docker run --rm alpine getent hosts deb.debian.org
```

## Local host records

`ansible/playbooks/hosts-records.yaml` owns two sets of `/etc/hosts` entries on
the Nomad clients, defined in `ansible/group_vars/nomad.yaml`:

- `*.internal` names for the nodes. FTL used to serve these to containers on the
  bridge; resolved now synthesises them from `/etc/hosts` and serves them on
  both stub addresses. `jobs/molecule.hcl` and `jobs/immich/immich.hcl` resolve
  node names this way and break without them.
- The headscale control plane. tailscaled resolves its control URL through
  getaddrinfo, so the pin keeps a node able to reach the control plane while its
  own DNS is broken.

`host` and `dig` ignore `/etc/hosts`, so verify with `getent`.

## Upstream recursion is IPv4 only

dionysus forwards to `9.9.9.9`, `149.112.112.112`, `1.1.1.1`, `1.0.0.1`.

It previously listed four IPv6 servers ahead of these, from the DS-Lite era when
the house was IPv6-native. The Blacknight FTTH line does not route to them, so
every lookup burned a timeout per dead server before reaching a working one —
usually just slow, but enough to fail gravity outright when it fetched ~20
blocklists at once. Do not re-add IPv6 upstreams without confirming
`ping6 2606:4700:4700::1111` actually succeeds from the NAS.

## Roaming clients

`dns.nameservers.global` in `external/headscale/config.yaml` is `192.168.0.5`
and nothing else — a single entry, deliberately, so every lookup goes through
the blocker and private names fail rather than being answered publicly.

The cost: that is a LAN address and dionysus is not a tailnet node, so reaching
it depends on hermes advertising `192.168.0.0/24` and that route being approved
and up. The old Pi-hole pair was addressed by tailnet IP and needed no route at
all. Putting tailscale on the NAS would restore the stronger guarantee.

## Break-glass: no DNS while away

If dionysus or the subnet route is down, a roaming client has no DNS at all —
MagicDNS is a `~.` catch-all, so public names fail too.

Per-client, immediately:

```sh
tailscale set --accept-dns=false     # public names work, private ones stop
```

For every client at once, add a public resolver to the control plane:

```sh
ssh ubuntu@141.147.74.4
sudo vi /opt/headscale/data/config.yaml   # add "- 9.9.9.9" under dns.nameservers.global
sudo docker restart headscale
```

**Revert it once home is back.** While it is in place, ad-blocking is bypassed
and a private name can get a public answer instead of failing.

## Verifying

```sh
# The resolver itself
dig +short @192.168.0.5 example.com

# A node: stub, upstream, and the container path
resolvectl status | grep -A3 '^Global'      # expect DNS Servers: 127.0.0.1:8600
getent hosts example.com                     # NSS path, not dig
getent hosts zeus.internal                   # /etc/hosts records
docker run --rm alpine getent hosts deb.debian.org

# Ad-blocking is live
dig +short @192.168.0.5 doubleclick.net      # expect 0.0.0.0
```

## History: why the pair is gone

The pair was added on 2026-09-08 for redundancy and split DNS, and removed six
days later. It was not redundant in practice — it introduced a shared failure
mode instead. Both nodes had their resolver surgery applied identically, so the
nsswitch defect above took out both at once, and it took the Nomad cluster with
it because the Docker daemon could no longer resolve a registry.

What actually made it expensive was that everything about it was
non-obvious: `dig` reported health while `getaddrinfo` failed, the documented
rollback would have left both nodes with no upstream at all, and the failure
surfaced two days later as unrelated-looking CSI placement errors.

One resolver that is understood beats two that are not. dionysus had been
running the whole time and was never part of the incident.
