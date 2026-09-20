# EdgeRouter X cutover and LAN renumber

Replacing the Blacknight-supplied router with an EdgeRouter X, and renumbering
the home LAN off `192.168.0.0/24` into RFC1918 `10.x` space at the same time.

These are two separate changes and the main thing that makes this go smoothly is
not doing them at the same moment. The router swap is reversible in two minutes
(plug the old one back in). Renumbering is not — it touches the Nomad/Consul
raft peer set, the Synology's NFS exports, the Pi-hole records every LAN client
depends on, and the Tailscale subnet route that roaming clients resolve DNS
through. Do the swap first, carrying both subnets, then renumber host by host.

## Addressing plan

**Reserved**: `10.42.0.0/16` — the homelab supernet. Nothing else may claim it.
**Configured today**: `10.42.0.0/24` — the single LAN segment.
**Advertised on the tailnet**: `10.42.0.0/16`.

| Host | Today | After |
|---|---|---|
| router | 192.168.0.1 | 10.42.0.1/24 (+ 192.168.0.1/24 during transition) |
| zeus | 192.168.0.3 | 10.42.0.3 |
| hermes | 192.168.0.4 | 10.42.0.4 |
| dionysus | 192.168.0.5 | 10.42.0.5 |
| DHCP pool | — | 10.42.0.100–10.42.0.200 |

Keeping the last octets means the repo diff in step 7 is a prefix substitution
and nothing else, which makes that sweep mechanical and reviewable.

### Why a /24 on the wire and a /16 on paper

Room to grow comes from the reservation, not from the netmask. A wider mask only
buys a wider broadcast domain, and this LAN will never approach 254 hosts. What
growth actually looks like here is *more segments* — IoT, guest, management —
and those want their own subnets and their own firewall zones, not more space on
the existing wire.

So the `/16` is a promise and the `/24` is a configuration. Future segments
carve out of the promise, with the third octet matching the VLAN ID — VLAN 20
becomes `10.42.20.0/24` on `switch0.20`, with its own DHCP subnet and its own
ruleset. Untagged stays `10.42.0.0/24`. Nothing renumbers.

Putting `/16` on `switch0` itself would close that door: the interface would own
the whole range and the first VLAN would mean renumbering again.

### Why the route advertised to the tailnet is the /16

`docs/Headscale.md` records that `approve-routes` **replaces the full list**, and
that this has already caused an outage. Advertising the supernet once means
adding a VLAN later never touches route approval at all. The `/16` is specific
enough to be safe and wide enough to never need revisiting.

### Why not anything inside 10.0.0.0/16

`terraform/oci/network.tf` puts the Oracle VCN on `10.0.0.0/16` with its subnet
at `10.0.0.0/24`; observability is `10.0.0.59`, worker is `10.0.0.97`, and OCI's
gateway for that subnet is `10.0.0.1`. observability runs with
`accept_routes: true` and *needs* the LAN subnet route —
`external/gatus/config.yaml` checks LAN addresses directly. Any advertised route
overlapping `10.0.0.0/24` lands in tailscaled's table 52, which is consulted
before `main`, in front of observability's own on-link subnet route and its
default gateway. That is the Gatus `internal` group going blind at best and the
instance losing its own network at worst — the same class of self-inflicted
black-hole the `accept_routes: false` comments on hermes and zeus already
document.

Moving the Oracle subnet is not a realistic alternative: subnet CIDRs are
immutable in OCI, both instances are `VM.Standard.E2.1.Micro` and so support a
single VNIC, and relaunching them into a new subnet would issue new ephemeral
public IPs and a new Oracle-assigned IPv6 `/64` — addresses that are load-bearing
in `hosts_headscale_pins`, Cloudflare, NS1 and the Gatus relay config.

**Never advertise `10.0.0.0/8`.** A roaming client that accepts it loses every
other `10.x` network it touches, including work VPNs and any future VCN.

## 1. Before touching anything

- **Capture the Blacknight router's config.** Screenshot or write down: every
  port forward (protocol, external port, internal host, internal port), every
  DHCP reservation with its MAC, the WAN connection type, and whether the WAN is
  VLAN-tagged. `ansible/host_vars/hermes.yaml` refers to "the ingress path the
  new port forwards depend on", so forwards exist and must be replicated —
  losing them silently moves public ingress back to the Oracle relay path.
- **The PPPoE handoff is VLAN 10 tagged**, with Blacknight's generic FTTH
  credentials. Confirmed from the box's pre-existing config, not from the ISP —
  if the session fails to authenticate at swap time, untagged on `eth0` is the
  fallback to try.
- **Confirm whether the line carries IPv6 (DHCPv6-PD).** `docs/Redesign-Plan.md`
  records that the nodes run no DHCPv6 client and lose their address if the
  router advertises stateful DHCPv6 rather than SLAAC. If you enable IPv6 on the
  ERX, it must be `service slaac`.
- **Pin the infrastructure hosts to static addresses on the hosts themselves**,
  still on `192.168.0.x/24` with gateway `192.168.0.1`. If hermes, zeus and
  dionysus currently get their addresses from Blacknight DHCP reservations, they
  will take a `10.42.0.x` lease the instant the ERX comes up, and you will be
  renumbering the cluster unplanned, at the worst possible moment. This step is
  what buys you control over the ordering.
- **Take backups**: `consul snapshot save`, `nomad operator snapshot save`, a
  DSM config export, and the Pi-hole Teleporter export. Record the Consul and
  Nomad server IDs now — `/opt/consul/node-id` and `/opt/nomad/server/node-id`
  on each node. You need them if step 6 needs recovery.
- **Note the current Pi-hole dnsmasq config.** `ansible/playbooks/dns.yaml`
  documents ~20 `address=` lines pointing service names at hermes at
  192.168.0.4. Those are not in the repo and the playbook deliberately preserves
  rather than owns them. They all need the new address in step 3.

## 2. Build the ERX on the bench

SSH keys go through the config, not `authorized_keys` — the file is rendered by
vyatta and hand edits are lost on commit:

```
configure
set system login user <user> authentication public-keys <key-id> type ssh-ed25519
set system login user <user> authentication public-keys <key-id> key AAAA...
commit
```

(or `loadkey <user> <file>` from operational mode).

Commit and save as separate steps, not as `commit ; save`. EdgeOS runs the
`save` even when the commit aborts, writing the last *successfully committed*
config to `/config/config.boot` while your pending edits stay live but unsaved —
which reads as if the changes were persisted when they were not.

Use `commit-confirm 5` rather than `commit` for anything touching interfaces,
firewall or NAT. It reverts automatically after five minutes unless you type
`confirm`, which turns a lockout into a wait. The box is managed over the
network it is being configured on, and the `switch0` address you are connected
through is deletable like any other — removing it drops the session mid-commit.
Move your management address to the new one and reconnect *before* deleting the
old, and keep `save` until after you have confirmed you are still reachable; an
unsaved lockout is fixed by power-cycling back into `/config/config.boot`,
whereas a saved one is not.

WAN, PPPoE on **VLAN 10** — Blacknight tags the handoff, so the session hangs
off a `vif` rather than `eth0` directly. `name-server none` matters: the
resolver of record is dionysus, and the router must not start handing out or
caching ISP answers. Credentials are Blacknight's generic FTTH pair
(`broadband@bk.network` / `broadband`), not per-customer secrets.

```
set interfaces ethernet eth0 description 'WAN - Blacknight ONT'
set interfaces ethernet eth0 vif 10 description 'Internet (PPPoE)'
set interfaces ethernet eth0 vif 10 pppoe 0 user-id 'broadband@bk.network'
set interfaces ethernet eth0 vif 10 pppoe 0 password 'broadband'
set interfaces ethernet eth0 vif 10 pppoe 0 mtu 1492
set interfaces ethernet eth0 vif 10 pppoe 0 default-route auto
set interfaces ethernet eth0 vif 10 pppoe 0 name-server none
set interfaces ethernet eth0 vif 10 pppoe 0 firewall in name WAN_IN
set interfaces ethernet eth0 vif 10 pppoe 0 firewall local name WAN_LOCAL
```

**Exactly one PPPoE unit 0.** EdgeOS names the interface after the unit number,
not the parent, so a session on `eth0 pppoe 0` and another on
`eth0 vif 10 pppoe 0` both claim `pppoe0` and conflict. If the tagged session
never authenticates, `delete interfaces ethernet eth0 vif 10` and move the same
stanza to `eth0` untagged — but do not leave both in place while testing.

Two things to know while building this with no WAN cable attached. `eth0` must
not be a member of `switch0` — check `show interfaces switch switch0
switch-port` and `delete interfaces switch switch0 switch-port interface eth0`
if it is, because PPPoE on a switch-port member never comes up. And every later
rule that names `pppoe0` — the NAT masquerade, the firewall attachments — will
warn *interface pppoe0 does not exist on this system* at commit. That is
expected on the bench: the interface appears only once the session is up, and
the rules are written regardless. Do check the unit numbers agree, though; a
masquerade rule pointing at `pppoe0` silently never matches a session that came
up as `pppoe1`.

MSS clamping. Skipping this is the classic PPPoE failure: ping works, small
pages load, TLS handshakes to some sites hang forever.

```
set firewall options mss-clamp interface-type pppoe
set firewall options mss-clamp mss 1452
```

LAN, carrying both subnets through the transition:

```
set interfaces switch switch0 description 'LAN'
set interfaces switch switch0 address 10.42.0.1/24
set interfaces switch switch0 address 192.168.0.1/24
```

The original bench build's `10.0.0.1/8` has to come off too — it covers
`10.42.0.0/24`, so it makes on-link determination ambiguous and puts dhcpd back
into the subnet overlap it refuses to commit. Remove it **last**, after moving
the workstation off `10.0.0.12/8` onto `10.42.0.12/24` and reconnecting on
`10.42.0.1`:

```
delete interfaces switch switch0 address 10.0.0.1/8
```

Doing it before the move deletes the address the session is running over.

The ERX taking `192.168.0.1` means every host still on the old subnet keeps a
working default gateway, and hosts on either subnet reach hosts on the other
through the router. That is what makes a host-by-host renumber possible instead
of a flag day.

Source NAT:

```
set service nat rule 5000 description 'masquerade to WAN'
set service nat rule 5000 outbound-interface pppoe0
set service nat rule 5000 type masquerade
set service nat rule 5000 protocol all
```

Firewall. The ERX default-accepts, and unlike the Blacknight box it is now the
only thing between the internet and two nodes whose `INPUT` policy is `ACCEPT`
with no rules (`docs/Redesign-Plan.md`):

```
set firewall name WAN_IN default-action drop
set firewall name WAN_IN rule 10 action accept
set firewall name WAN_IN rule 10 state established enable
set firewall name WAN_IN rule 10 state related enable
set firewall name WAN_IN rule 20 action drop
set firewall name WAN_IN rule 20 state invalid enable
set firewall name WAN_LOCAL default-action drop
set firewall name WAN_LOCAL rule 10 action accept
set firewall name WAN_LOCAL rule 10 state established enable
set firewall name WAN_LOCAL rule 10 state related enable
set firewall name WAN_LOCAL rule 20 action drop
set firewall name WAN_LOCAL rule 20 state invalid enable
```

If you enable IPv6, mirror this with `ipv6-name WANv6_IN` / `WANv6_LOCAL` before
the prefix is up. Port 53 is the one to think about first: FTL binds the
wildcard, so a globally routable prefix plus a permissive v6 policy is an open
resolver.

DHCP. Short lease during the window so clients pick up the new DNS server and
search domain in minutes rather than hours; raise it afterwards. `domain-name
internal` is the DHCP third of the search domain the ADR specifies, alongside
`dns.search_domains` in headscale and the resolved drop-in on the nodes:

If the box already carries a DHCP subnet from an earlier bench session, remove
it first — an overlapping declaration under the same shared-network aborts the
commit, and its static mappings hold the addresses the new ones want:

```
delete service dhcp-server shared-network-name LAN subnet 10.0.0.0/8
```

```
set service dhcp-server disabled false
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 default-router 10.42.0.1
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 dns-server 192.168.0.5
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 domain-name internal
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 lease 600
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 start 10.42.0.100 stop 10.42.0.200
```

`dns-server` stays on the old dionysus address until step 4 moves it. Clients on
`10.42.0.x` reach `192.168.0.5` through the router's second LAN address.

dhcpd wants a subnet declaration for every subnet on an interface it serves, and
`switch0` carries `192.168.0.1/24` throughout the transition. If it refuses to
start with *No subnet declaration for switch0*, declare the old subnet with no
pool — it exists only to satisfy dhcpd, and nothing is ever handed out on it:

```
set service dhcp-server shared-network-name LAN subnet 192.168.0.0/24 default-router 192.168.0.1
```

The *"Multiple subnets ... share the same physical network"* warning that
follows is correct and intended; that is the dual-subnet transition. Only an
*overlap* between declared subnets is an actual error.

Static mappings for anything that had a reservation, one per device:

```
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 static-mapping <name> ip-address 10.42.0.N
set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 static-mapping <name> mac-address <mac>
```

The workstation belongs here rather than in the static-on-the-host category —
nothing in the repo addresses it, and only a DHCP client receives the `internal`
search domain. Hand-configure it and `ssh hermes` quietly fails there while
`ssh hermes.internal` works. Static addressing is for hosts that must come up
without a DHCP server: zeus, hermes, dionysus.

**Do not create mappings for zeus, hermes or dionysus yet** unless those three
are already statically addressed on the hosts themselves. A reservation at
`10.42.0.3/.4/.5` moves a DHCP client the moment the ERX comes up — which is
the unplanned cluster renumber that step 1 exists to prevent, arriving during
the router swap while PPPoE is still being debugged. Add them when step 4 and
step 6 are actually being done. The switch and AP are fine to map now; they
re-adopt harmlessly.

Port forwards, from the inventory in step 1. Use the `port-forward` node rather
than hand-written destination NAT rules: `auto-firewall` maintains the `WAN_IN`
accepts, and `hairpin-nat` covers LAN clients that reach a service by its public
address. `wan-interface` must be `pppoe0` — inbound traffic arrives already
decapsulated, so matching `eth0.10` underneath the session never sees it.

```
set port-forward wan-interface pppoe0
set port-forward lan-interface switch0
set port-forward auto-firewall enable
set port-forward hairpin-nat enable
set port-forward rule 1 description https
set port-forward rule 1 original-port 443
set port-forward rule 1 protocol tcp_udp
set port-forward rule 1 forward-to address 10.42.0.4
set port-forward rule 1 forward-to port 443
set port-forward rule 2 description http
set port-forward rule 2 original-port 80
set port-forward rule 2 protocol tcp_udp
set port-forward rule 2 forward-to address 10.42.0.4
set port-forward rule 2 forward-to port 80
set port-forward rule 3 description mumble
set port-forward rule 3 original-port 64738
set port-forward rule 3 protocol tcp_udp
set port-forward rule 3 forward-to address 10.42.0.4
set port-forward rule 3 forward-to port 64738
```

`tcp_udp` on 64738 is required — Mumble uses TCP for control and UDP for voice.

**Do not also write `service nat type destination` rules for these ports.** The
two mechanisms are mutually exclusive per port; configuring both leaves which
DNAT wins down to evaluation order. Pick one, and if you pick `port-forward`,
remember its accepts do not appear in `show firewall name WAN_IN` — verify with
`sudo iptables -t nat -L -n -v` instead.

Exactly one masquerade rule, for the same reason:

```
set service nat rule 5000 description 'masquerade to WAN'
set service nat rule 5000 outbound-interface pppoe0
set service nat rule 5000 type masquerade
set service nat rule 5000 protocol all
```

Offload, and turn off DPI. The ER-X is a MediaTek MT7621 and will not clear much
more than ~200Mbps of PPPoE NAT in software. Requires a reboot to take effect:

```
set system offload hwnat enable
set system offload ipsec enable
set system traffic-analysis dpi disable
set system traffic-analysis export disable
commit
reboot
```

**`hwnat` is the only offload engine this platform has.** The `system offload
ipv4 forwarding|pppoe|vlan` nodes exist in the CLI tree because it is shared
across the whole EdgeOS family, but they are Cavium-specific (ERLite-3, ER-8,
ER-4) and the ER-X rejects them at commit with *platform does not support ipv4
forwarding offload*. Do not go looking for a syntax that works; there isn't one.

Two consequences. `hwnat` accelerates IPv4 only, so if the line hands out a
`/56` then IPv6 is forwarded in software and will be markedly slower — measure
it rather than assuming, given the nodes prefer v6 to reach the control plane.
And DPI, smart-queue and traffic-policies all push matching flows back onto the
software path, which is why `traffic-analysis` is disabled in the same block
rather than as a tidiness measure.

Confirm after the reboot with `show ubnt offload`, then measure actual
throughput over PPPoE before trusting the ER-X with the full line rate.

Leave the ERX's own DNS forwarding off and point the router at a public resolver
for its own lookups — the router resolving through dionysus makes NTP and
firmware checks depend on a host that depends on the router. The default config
ships with `service dns forwarding listen-on switch0`, which puts a second
resolver on the LAN; `docs/DNS.md` exists because one resolver that is
understood beats two that are not.

```
delete service dns forwarding
set system name-server 9.9.9.9
set system time-zone Europe/Dublin
```

The timezone matters more than it looks: the box defaults to UTC, and its logs
get correlated against Gatus alerts and Nomad events during the cutover.

Check `name-server none` survived on the PPPoE session — `auto` reinstates
Blacknight's resolvers on the router and it has a habit of coming back after
edits to the surrounding stanza.

## 3. Swap the router

Window: everything drops for the length of the PPPoE handshake, and public
ingress drops until the forwards are verified.

1. Old router out, ERX in. WAN to the ONT, LAN to the UniFi switch.
2. `show interfaces pppoe pppoe0` — session up, address is the expected public
   IPv4 (`185.152.73.180` unless Blacknight has moved it; if it has, the
   Cloudflare records in `terraform/cloudflare` need the new one).
   If `pppoe0` still does not exist now that it is cabled, work through
   `show interfaces ethernet eth0` (carrier), `show log tail | match pppd`, then
   the three usual causes in order: no carrier at the ONT port, a VLAN tag
   needed (move the stanza to `eth0 vif 10 pppoe 0`; the interface is still
   called `pppoe0`), or the username format — Blacknight generally issues
   `user@domain` rather than a bare username.
3. `ping 9.9.9.9` from the router, then from a LAN client.
4. From a client on the new pool: check it got `10.42.0.x`, gateway `10.42.0.1`,
   DNS `192.168.0.5`, and that `dig example.com` and `dig hermes.internal` both
   answer. Nothing on the cluster has moved yet, so all of that should work
   unchanged — if it doesn't, the problem is the router, and rolling back is
   still one cable swap.
5. Verify MTU end to end from a LAN client, not from the router:
   `ping -M do -s 1464 1.1.1.1` (1464 + 28 = 1492) must succeed and
   `-s 1472` must fail. Then load a few large HTTPS sites.
6. Probe the port forwards from outside (phone on mobile data, or
   `curl` from observability.cloud).

**Stop here and soak for a day.** The LAN is renumbering itself gradually as
leases roll; the infrastructure is untouched. Nothing below is urgent.

## 4. Renumber dionysus

This is the one that breaks DNS for everyone if it goes wrong, so do it alone.

1. DSM → Control Panel → Network → Network Interface → LAN: static
   `10.42.0.5`, mask `255.255.255.0`, gateway `10.42.0.1`, DNS `127.0.0.1`.
2. **NFS exports.** `/volume1/data` and `/volume1/homes` are almost certainly
   scoped to `192.168.0.0/24`. Add `10.42.0.0/16` — the supernet, so future
   segments do not need another visit. The Immich CSI volumes
   (`jobs/immich/immich-{data,homes,postgres-backup}.hcl`) mount by the name
   `dionysus.internal`, so they follow the rename — but they fail on the export
   rule if you forget this.
3. **DSM firewall rules**, same — add `10.42.0.0/16` alongside the old range.
4. **Pi-hole**: update the ~20 `address=` lines that point service names at
   `192.168.0.4`, and re-run `ansible-playbook ansible/playbooks/dns.yaml`
   (after step 7) to regenerate the `host-record=` lines. Check the listening
   mode still permits the new subnet.
5. **iSCSI / synology-csi**: `nomad volume status <id>` on the Synology-backed
   volumes and check whether the DSM address is baked into the external ID or
   publish context. If it is, those volumes need deregistering and
   re-registering after `jobs/csi/synology-csi-controller.hcl` is updated.
6. Flip DHCP:
   `set service dhcp-server shared-network-name LAN subnet 10.42.0.0/24 dns-server 10.42.0.5`
7. Verify: `dig +short @10.42.0.5 example.com`, `dig +short @10.42.0.5 doubleclick.net`
   (expect `0.0.0.0`), and from a node `getent hosts hermes` plus
   `docker run --rm alpine getent hosts deb.debian.org` — the container path
   through `172.17.0.1` is the half that breaks quietly (`docs/DNS.md`).

## 5. Renumber the UniFi switch and access point

The controller runs on zeus (`jobs/unifi/unifi.hcl`) and devices reach it by
address. They are on the same L2, so L2 discovery should re-find them, but have
`set-inform http://10.42.0.3:8080/inform` ready over SSH on each device. Do this
*before* zeus moves in step 6, then again after, or you will be re-adopting
blind over a network you just changed.

## 6. Renumber the cluster nodes

This is the step with real blast radius, and it is separable from everything
above. Two ways to take it.

**Path A — defer it (recommended).** Leave hermes and zeus on
`192.168.0.3/.4` and leave `192.168.0.1/24` on the ERX. Everything else in the
homelab is on `10.42.0.x`, the router swap is done, and the cluster is
addressed by name from the jobs that matter. Then fold the address change into
Phase 5 of `docs/Redesign-Plan.md`, which moves Consul `bind_addr` and Nomad
`advertise` onto tailnet addresses and a third voter on observability.cloud.
With three voters you can roll one node at a time and never lose quorum, and
after it the cluster's raft addresses stop caring about the LAN prefix at all.
The cost is carrying a second subnet on the router for a while, which is free.

**Path B — do it now.** The obstacle is `bootstrap_expect = 2`: quorum is both
servers, so there is no leader available to commit a peer address change while
either one is down. You cannot roll these one at a time. Plan a window:

1. Snapshot Consul and Nomad. Have the server IDs from step 1 to hand.
2. Stop Nomad then Consul on both nodes.
3. Set static `10.42.0.3/24` and `10.42.0.4/24`, gateway `10.42.0.1`, on each.
4. Land the repo changes from step 7 and run
   `ansible-playbook ansible/playbooks/configure-nomad-consul.yaml` so
   `bind_addr` and `advertise` are rewritten before anything starts.
5. Start Consul on both. Give it a minute. If `consul operator raft list-peers`
   shows the old addresses and no leader, recover: write
   `/opt/consul/raft/peers.json` on **both** nodes and restart —

   ```json
   [
     {"id": "<zeus-node-id>",   "address": "10.42.0.3:8300", "non_voter": false},
     {"id": "<hermes-node-id>", "address": "10.42.0.4:8300", "non_voter": false}
   ]
   ```

   Same shape for Nomad at `/opt/nomad/server/raft/peers.json` on port `4647`.
   Expect to need this rather than hoping you won't.
6. Start Nomad. `nomad operator raft list-peers`, `nomad node status` — two
   clients, both ready. Watch the CSI plugins re-register before declaring
   victory; `docs/DNS.md` records a two-day outage that surfaced only as
   unrelated-looking CSI placement errors.

One thing to fix regardless of path: `retry_join` in
`ansible/playbooks/templates/consul/consul.hcl.j2` is built from bare inventory
names, and bare names on the nodes resolve only via the `internal` search domain
into unicast DNS — i.e. via dionysus. Consul forming a cluster therefore depends
on the resolver being up and correct, which during a renumber is exactly what
isn't. Pin `retry_join` to addresses, or add short-name aliases to the
`/etc/hosts` block in `ansible/playbooks/hosts-records.yaml`.

## 7. Repo sweep

A prefix substitution, but check each one — some are CIDRs, not hosts, and the
right width differs: `10.42.0.0/24` where it means *this segment*,
`10.42.0.0/16` where it means *the homelab*.

| File | What | Width |
|---|---|---|
| `ansible/hosts:2-3` | `ansible_host` for zeus, hermes | host |
| `ansible/group_vars/nomad.yaml:16-18` | `hosts_internal_records` | host |
| `ansible/host_vars/hermes.yaml:11`, `zeus.yaml:7` | `tailscale_advertise_routes` | `/16` |
| `ansible/playbooks/dns.yaml:35,93` | `pihole_api`, the `dig` target | host |
| `ansible/playbooks/templates/consul/consul.hcl.j2:4` | `bind_addr` network filter | `/24` |
| `ansible/playbooks/templates/consul/consul.hcl.j2:38` | `recursors` | host |
| `external/headscale/config.yaml:55` | `nameservers.global` — **and** hand-apply to `worker.cloud:/opt/headscale/data/config.yaml`; headplane edits in place, the repo copy is not deployed | host |
| `external/gatus/config.yaml:224,233,243,252,264,296` | all six `internal`-group checks | host |
| `jobs/traefik.hcl:127` | `trustedIPs` — replace `192.168.0.0/16` with `10.42.0.0/16` | `/16` |
| `jobs/traefik.hcl:240,247` | synodrive and video backends on dionysus | host |
| `jobs/csi/synology-csi-controller.hcl:41` | DSM client host | host |
| `jobs/headscale/headscale.hcl:122` | nameserver entry | host |
| `jobs/paperless/paperless.hcl:77` | `PAPERLESS_ALLOWED_HOSTS` | host |
| `docs/{DNS,Headscale,Disaster-Recovery,Redesign-Plan}.md`, `docs/adr/0001-*.md` | prose and diagrams | — |

The `internal-only` ipAllowList middleware planned in Phase 4 of
`docs/Redesign-Plan.md` should use `10.42.0.0/16` too, so a future VLAN is
covered without editing Traefik.

`jobs/archive/update-plex.hcl:29` is archived; update it or leave it, but don't
let it look current.

Then re-run, in order: `hosts-records.yaml`, `dns.yaml`, `gatus.yaml`, and
re-submit the touched jobs.

## 8. Tailscale routes

Changing what hermes and zeus advertise needs re-approval in headscale, and
`approve-routes` **replaces the full list** — the footgun documented in
`docs/Headscale.md`. Approve the union, and remember hermes also carries
`0.0.0.0/0, ::/0` as the exit node.

During the transition advertise both, then drop the old one:

```
tailscale_advertise_routes: "10.42.0.0/16,192.168.0.0/24"
```

hermes' full approved list while both are live:
`10.42.0.0/16,192.168.0.0/24,0.0.0.0/0,::/0`. zeus': the two subnets only.

Test failover **from the LAN, never over the tailnet**: stop tailscaled on
hermes, confirm a roaming client still resolves through dionysus via zeus within
~30s, and that the Gatus `internal` group stays green.

## 9. Verification

- Internet from the LAN; MTU probe at 1464 passes, 1472 fails; large HTTPS sites
  load.
- Every port forward answers from outside.
- `dig +short @10.42.0.5 example.com`; an ad domain returns `0.0.0.0`.
- On each node: `resolvectl status | grep -A3 '^Global'` shows `127.0.0.1:8600`;
  `getent hosts hermes` and `hermes.internal`;
  `docker run --rm alpine getent hosts deb.debian.org`.
- `consul operator raft list-peers`, `nomad operator raft list-peers`,
  `nomad node status`, CSI plugins healthy, a volume-constrained job places.
- Gatus: all groups green, `internal` included.
- From a roaming client: `tailscale dns query vault.dbyte.xyz`, then reach a LAN
  address through the subnet route.
- Public sites serve, through whichever ingress path is primary.

## 10. Decommission the old subnet

Only after a week of the above staying green, and only once nothing answers on
`192.168.0.x`:

```
delete interfaces switch switch0 address 192.168.0.1/24
```

Drop `192.168.0.0/24` from `tailscale_advertise_routes`, re-approve the reduced
list on both nodes, raise the DHCP lease back to something sane, and grep the
repo for the old prefix one last time.

## Adding a segment later

The reservation exists so this is additive rather than another renumber. Third
octet = VLAN ID:

```
set interfaces switch switch0 vif 20 address 10.42.20.1/24
set interfaces switch switch0 vif 20 description 'IoT'
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 default-router 10.42.20.1
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 dns-server 10.42.0.5
set service dhcp-server shared-network-name IOT subnet 10.42.20.0/24 start 10.42.20.100 stop 10.42.20.200
set interfaces switch switch0 vif 20 firewall in name IOT_IN
```

Tag the port on the UniFi switch, write `IOT_IN` to permit DNS to `10.42.0.5`
and the internet but not the rest of `10.42.0.0/16`, and leave the tailnet route
alone — the advertised `/16` already covers it.

## Rollback

- **Before step 4**: unplug the ERX, plug the Blacknight router back in.
  Everything infrastructural is still on its old address.
- **After step 4**: put dionysus back on `192.168.0.5` and the DHCP `dns-server`
  with it. The old subnet is still live on the router, so this is a single
  change.
- **After step 6 Path B**: the Consul and Nomad snapshots from step 1, restored
  onto nodes returned to their old addresses. This is the point of no cheap
  return, which is the argument for Path A.
