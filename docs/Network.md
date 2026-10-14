# Home network

The house sits behind an EdgeRouter X (since 2026-10-14) on Blacknight Home
Fibre 500, with a static IPv4 (`185.152.73.180`) and a static IPv6 that is not
yet enabled. The ERX config itself is the source of truth for the router; this
page covers why it is shaped the way it is and what is left to do.

## Layout

| | |
|---|---|
| WAN | `eth0` VLAN 10, PPPoE (`pppoe0`), MTU 1492, MSS clamp 1452 |
| LAN | `switch0` (`eth1`–`eth4`) carries `10.42.0.1/24` **and** `192.168.0.1/24` |
| Clients | `10.42.0.0/24`, ERX DHCP `.100`–`.200`, search domain `internal`, DNS `192.168.0.5` |
| Infrastructure | still `192.168.0.0/24`: zeus `.3`, hermes `.4`, dionysus `.5` (static on the hosts) |
| Reservations | usw-lite `10.42.0.2`, uap6 `10.42.0.8`, archdesktop `10.42.0.12` |
| Resolver | Pi-hole on dionysus. The ERX does no DNS forwarding and resolves via `9.9.9.9` itself |
| Tailnet routes | `192.168.0.0/24` via zeus and hermes (both must be *approved*, see `docs/Headscale.md`); `10.42.0.0/16` pending |
| IPv6 | off on the ERX. `WANv6_IN`/`WANv6_LOCAL` exist, default drop |
| Management | `ssh ubnt@10.42.0.1` (also answers on `192.168.0.1`) |

The two subnets share one L2 and the ERX routes between them, so a client on
`10.42.0.x` reaches the infrastructure on `192.168.0.x` without anything
special. That is what lets the infrastructure renumber happen later, in one
window (below).

## Addressing

`10.42.0.0/16` is reserved for the homelab; `10.42.0.0/24` is what is
configured. Growth means more segments, not a wider mask: VLAN *N* becomes
`10.42.N.0/24` on `switch0.N`. Putting `/16` on `switch0` itself would make the
first VLAN another renumber. The tailnet route is advertised as the `/16` once,
so a new VLAN never touches route approval.

**Nothing inside `10.0.0.0/16`.** The Oracle VCN is `10.0.0.0/16` (subnet
`10.0.0.0/24`, observability `10.0.0.59`, worker `10.0.0.97`, gateway
`10.0.0.1`), and observability runs `accept_routes: true` because Gatus checks
LAN addresses. An overlapping tailnet route lands in table 52, ahead of
observability's own subnet and default route. OCI subnets are immutable and the
Micro instances have a single VNIC, so moving the VCN would mean new public
IPs everywhere they are pinned. **Never advertise `10.0.0.0/8`** either: a
roaming client that accepts it loses every other `10.x` network it touches.

## Ingress

The ERX forwards 80, 443 and 64738 (TCP+UDP) to hermes `192.168.0.4`, with
hairpin NAT. Public names resolve to the home IP; the Oracle relay
(`132.226.210.138`) is warm standby and serves every public router too.

Traefik decides what is public, not DNS:

- **Public** routers opt in with
  `traefik.http.routers.<name>.entrypoints=websecure,websecure-proxied`, and
  their name goes in `terraform/cloudflare/records-public.tf`.
- **Private** routers carry `traefik.http.routers.<name>.middlewares=internal-only@file`
  (LAN, `10.42.0.0/16`, tailnet). They have no public DNS record and answer 403
  from the internet even to a hand-written `Host` header.
- `websecure-proxied` (the relay's PROXY-protocol entrypoint) is not
  `asDefault`, so a router with neither tag is reachable from the LAN and
  the home IP but not through the relay. New services start that way.

Failover to the relay is pointing the public records at `132.226.210.138`
(`var.ingress_ipv4` in both terraform roots; `pint.ing` lives on NS1).

## Pi-hole overrides

Each `address=/<name>/192.168.0.4` for a **leaf** name has a matching
`local=/<name>/`. Without it dnsmasq forwards AAAA and HTTPS queries upstream,
caches Cloudflare's answer, and starts answering A lookups from that cache —
about a third of answers used to go to the relay. **Never `local=` a zone
apex**: it answers every type for the whole zone locally, so SOA/MX/TXT vanish
on the LAN, which broke Traefik's ACME zone lookup on 2026-10-14 and got
`*.james-hackett.ie` rate-limited. Traefik's DNS challenge now uses public
resolvers regardless.

## Traps

- **A static config file doesn't prove a static address.** hermes and zeus had
  `inet static` in `/etc/network/interfaces` and a `dhclient` still running from
  boot. At the first renewal after the ERX went in, zeus swapped `192.168.0.3`
  for a `10.42` lease, Consul and Nomad (two voters, no tolerance) lost quorum,
  and Nomad rescheduled half the cluster. Check `pgrep -a dhclient` is empty and
  `ip -4 addr` shows `valid_lft forever`. To retire a stray client keep the
  address: `kill -9` it (a clean stop runs the release script), then
  `ip addr change <addr>/24 dev <if> valid_lft forever preferred_lft forever`.
- **A lost Traefik allocation loses its certificates.** `ephemeral_disk`
  migrates on a normal update, not when the allocation is marked lost.
- **Nomad does not restart a dead device plugin.** If home-assistant won't place
  after an outage, check zeus reports the ConBee (`1cf1/0030`) under
  `nomad node status -self -verbose`; `systemctl restart nomad` on zeus brings
  the USB plugin back.
- **eth1 negotiating 100 Mb/s means a bad cable or seating**, and the flapping
  that comes with it drops large packets — which looks like an MTU or `hwnat`
  fault and is neither. Check `show interfaces ethernet eth1 physical`.
- **ERX config hygiene:** `commit-confirm 5` for anything touching interfaces,
  firewall or NAT; `commit` and `save` as separate steps (a failed commit still
  saves the previous config). Exactly one PPPoE unit 0, and `port-forward
  wan-interface` must be `pppoe0`. `hwnat` is the only offload engine on this
  platform.

## Remaining: the infrastructure renumber

dionysus, zeus and hermes move to `10.42.0.5/.3/.4` together, in one window,
ideally after Phase 5 (third voter over the tailnet) so quorum survives one node
at a time.

dionysus cannot go first. It is the block storage under most of the cluster:

- Eleven Synology iSCSI CSI volumes have `"dsm": "192.168.0.5"` in their Nomad
  volume context, which can't be changed in place — each needs
  `nomad volume deregister` + `register` with its job stopped (the LUN is
  untouched).
- The nodes hold live iSCSI sessions to `192.168.0.5:3260`; changing the
  address under running jobs removes their block devices mid-write.
- `jobs/csi/synology-csi-controller.hcl` reaches DSM at `192.168.0.5:5000`.
- All five NFS exports (`data`, `media`, `personal`, `homes`, `backups`) are
  scoped to `192.168.0.0/24`. Add `10.42.0.0/16`.

The window, in order:

1. Snapshot Consul and Nomad; note server IDs (`/opt/consul/node-id`,
   `/opt/nomad/server/node-id`). Advertise and approve
   `10.42.0.0/16,192.168.0.0/24` on zeus and hermes first (hermes also
   `0.0.0.0/0,::/0`).
2. Stop the CSI-backed jobs. Re-point UniFi devices
   (`set-inform http://10.42.0.3:8080/inform`) before and after zeus moves.
3. dionysus: DSM static `10.42.0.5/24`, gateway `10.42.0.1`, DNS `127.0.0.1`;
   NFS exports; update the `address=` lines and Pi-hole's `dns.hosts`;
   ERX DHCP `dns-server 10.42.0.5`.
4. zeus and hermes: static `10.42.0.3/.4`, gateway `10.42.0.1`. With two voters
   expect to need `peers.json` (`/opt/consul/raft/`, port 8300;
   `/opt/nomad/server/raft/`, port 4647) on **both** nodes.
5. Repo sweep (below), re-run `hosts-records.yaml`, `dns.yaml`,
   `configure-nomad-consul.yaml`, `gatus.yaml`; update the CSI controller;
   re-register the eleven volumes; start the jobs.
6. Verify: Gatus all green; `consul`/`nomad operator raft list-peers`; CSI
   plugins healthy and a volume job places; `docker run --rm alpine getent
   hosts deb.debian.org` on a node (the container DNS path breaks quietly).
7. After a quiet week: `delete interfaces switch switch0 address
   192.168.0.1/24`, drop `192.168.0.0/24` from the tailnet routes, raise the
   DHCP lease from 600s.

Repo sweep — `10.42.0.0/24` where it means this segment, `10.42.0.0/16` where
it means the homelab:

| Where | What |
|---|---|
| `ansible/hosts` | `ansible_host` for zeus, hermes |
| `ansible/group_vars/nomad.yaml` | `hosts_internal_records` |
| `ansible/host_vars/{hermes,zeus}.yaml` | `tailscale_advertise_routes` (`/16`) |
| `ansible/playbooks/dns.yaml` | `pihole_api`, the `dig` target |
| `ansible/playbooks/templates/consul/consul.hcl.j2` | `bind_addr` filter (`/24`), `recursors` |
| `external/headscale/config.yaml` | `nameservers.global` — and hand-apply on worker (headplane owns the live file) |
| `external/gatus/config.yaml` | `internal` group, private-app `dns-resolver` |
| `jobs/traefik.hcl` | `trustedIPs`, `internal-only` (drop `192.168.0.0/24`), synodrive/video backends |
| `jobs/csi/synology-csi-controller.hcl` | DSM host |
| `jobs/paperless/paperless.hcl` | `PAPERLESS_ALLOWED_HOSTS` |
| `docs/{DNS,Headscale,Disaster-Recovery,Redesign-Plan}.md`, `docs/adr/0001-*.md` | prose |

Rollback before step 3 costs nothing. After step 4 it means restoring the
snapshots onto nodes put back on their old addresses.

## Adding a segment

Third octet = VLAN ID:

```
set interfaces switch switch0 vif 20 address 10.42.20.1/24
set interfaces switch switch0 vif 20 description 'IoT'
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 default-router 10.42.20.1
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 dns-server 10.42.0.5
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 start 10.42.20.100 stop 10.42.20.200
set interfaces switch switch0 vif 20 firewall in name IOT_IN
```

Tag the port on the UniFi switch and write `IOT_IN` to allow DNS to dionysus
and the internet but not the rest of `10.42.0.0/16`. The tailnet `/16` already
covers it.
