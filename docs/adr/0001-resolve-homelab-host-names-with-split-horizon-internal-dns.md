# 1. Resolve homelab host names with split-horizon .internal DNS

Date: 2026-09-18

## Status

Accepted

## Context

Hosts in the homelab need to be addressable by short name (`hermes`) and by fully
qualified name (`hermes.internal`), from the LAN, from the Nomad nodes themselves,
and from roaming clients. Today neither form works reliably.

The `.internal` names resolve only because `ansible/playbooks/hosts-records.yaml`
writes them into `/etc/hosts` on the two Nomad nodes. Nothing serves them to any
other device. The `internal` search domain, which is what made short names work,
came from a static `/etc/resolv.conf` rendered by the Pi-hole playbook. That
playbook and its template were deleted when the redundant Pi-hole pair was
decommissioned on 2026-09-14, so the suffix lost its owner and bare names stopped
resolving. The generator that rendered records to both resolvers,
`scripts/sync-dns.sh` driven by `ansible/playbooks/dns.yaml`, was deleted in the
same change.

Consul runs on hermes and zeus and serves `.consul`. The nodes recurse through
their local agent, so it is already load-bearing for the cluster. It knows only
hosts running an agent, which means `hermes.node.consul` works while dionysus, the
router, the switch, the access point, phones and laptops are not in the catalogue
at all. Covering them would mean running agents on a Synology NAS and UniFi
hardware, or registering external nodes by hand.

dionysus (192.168.0.5) is the only LAN resolver. The router's DHCP hands out its
address along with the domain `lan`. The router's `DHCPv4.Server.Pool.{i}.DomainName`
is `PARAM_READ_WRITE` in its TR-181 model, so the domain it advertises can be
changed, although whether it applies without a reboot has not been verified.

headscale serves MagicDNS with `base_domain: ts.dbyte.xyz` and an
`extra_records_path` file. That file survived the Pi-hole removal and is still
being served; it maps service names to hermes' tailnet address, `100.64.0.1`, so a
roaming client reaches them over a direct peer path rather than depending on the
`192.168.0.0/24` subnet route.

Two constraints shape any answer. systemd-resolved does not send single-label
names to unicast DNS - it routes them to LLMNR and mDNS - so short names cannot be
made to work by publishing records alone. And the Nomad nodes currently have no
global IPv6 address, only an RA default route; publishing AAAA records for hosts in
that state has already caused outages, including dionysus' gravity failures and
stalled lookups against `headscale.dbyte.xyz`.

Alternatives considered were putting every host in Consul, which cannot reach
non-members; standing up a dedicated authoritative server such as CoreDNS with a
zone file, which is more conventional DNS but adds a component when dionysus
already answers queries; and keeping records only in `/etc/hosts`, which is simple
but never reaches a phone or a laptop.

## Decision

We will name every homelab host `<host>.internal` and make both the short and
fully qualified forms resolve, using split-horizon DNS so that a name returns the
address the querying client can actually reach.

We will keep one source of truth in this repository - a `homelab_hosts` variable
mapping each host to its LAN address and, where it has one, its tailnet address -
and render it to three publishers from a single generator, restoring the pattern
`scripts/sync-dns.sh` provided. dnsmasq `host-record` lines on dionysus will serve
LAN clients their LAN addresses. headscale `extra_records` will serve tailnet
clients the tailnet addresses, matching how service names are already published
there. `/etc/hosts` on the Nomad nodes, already owned by `hosts-records.yaml`,
will keep the cluster resolving its own members when no resolver is reachable.

We will make short names work by pushing `internal` as a search domain in all
three places rather than by relying on single-label queries: the router's DHCP
`DomainName`, `dns.search_domains` in headscale, and a systemd-resolved drop-in on
the nodes.

We will publish A records only. AAAA records are deferred until a host has a
verified global IPv6 address, and that condition reopens this part of the
decision; the generator will gate each family on what the host actually has rather
than on what it is configured to want.

We will keep Consul for service discovery under `.consul` and will not use it for
host records.

## Consequences

Short names work from every client rather than only where a hand-written file
happens to exist, and hosts that will never run a Consul agent - the NAS, the
router, the switch, the access point - are covered on the same terms as the Nomad
nodes. Roaming clients resolve host names over a direct peer path, so remote
access no longer depends on the subnet route being advertised, approved and up.
The cluster keeps resolving its own members if dionysus is down, because
`/etc/hosts` is independent of it.

dionysus becomes a single point of failure for LAN name resolution. This is
accepted deliberately: the previous attempt at redundancy coupled both Nomad nodes
into one resolver and a single defect took the cluster down with it, and the
`/etc/hosts` and `extra_records` layers mean the failure is now limited to LAN
clients losing names rather than the cluster losing storage.

Three publishers mean three places for records to drift apart. The single
generator is the mitigation, and it has to be written; deleting it was easy and
rebuilding it is the main cost of this decision. Until it exists, records added by
hand in one place will not appear in the others.

Split-horizon means the same name deliberately returns different answers depending
on where the query comes from. This is the point, but it makes debugging harder,
because comparing results between two machines is no longer a valid test of whether
DNS is correct.

Changing the router's DHCP `DomainName` from `lan` to `internal` affects every DHCP
client, and each picks it up only at lease renewal, so the change will appear to
work inconsistently for a while. Whether the router applies it without a reboot
needs verifying.

Publishing no AAAA records means an IPv6-only client cannot resolve homelab hosts.
There are none today, and the alternative has already caused outages, so the cost
is currently theoretical. It stops being theoretical if IPv6 is restored and this
decision is not revisited.

`.internal` cannot hold publicly trusted certificates, so anything needing a
browser-trusted name continues to use the existing `dbyte.xyz` records through
Traefik. Host names and service names therefore remain two separate namespaces,
which is a distinction anyone working on this has to keep in mind.
