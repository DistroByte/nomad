# Resilient Homelab Redesign

## Context

The homelab (repo: `~/personal/nomad`) runs a 2-node Nomad/Consul cluster (hermes 192.168.0.4, zeus 192.168.0.3 — Optiplex 7040s, both server+client, `bootstrap_expect=2`), a Synology DS920+ (dionysus, 192.168.0.5) providing Pi-hole DNS + CSI/NFS storage, and two Oracle always-free nodes: worker.cloud (Headscale control plane) and observability.cloud (nginx L4 relay + Gatus). Home WAN is DS-Lite (no public IPv4); all public traffic enters via the Oracle relay → Traefik pinned to hermes.

**Why change** — documented SPOFs and real outages:
- Pi-hole on dionysus is the acknowledged DNS SPOF; roaming tailnet clients reach it only via hermes's subnet route, so hermes down = DNS dead remotely *and* Gatus `internal` goes blind.
- 2-node Raft tolerates zero failures. Traefik, the only subnet router, Immich PG primary, photo MySQL, and the Gatus heartbeat are all pinned to hermes.
- Every `Host()` service is internet-reachable (both websecure entrypoints are `asDefault`).
- No offsite backups; Vaultwarden (holds the Ansible vault password — circular recovery dependency) has no app-level backup; Headscale state exists only on worker.cloud.
- No Terraform; OCI security lists are hand-managed allow-all; Nomad has no ACLs/TLS; `headscale:latest` with `pull: always` runs the control plane.
- A UniFi Cloud Gateway Fibre arrives (~after 2026-09-12) on a new Blacknight line — public IPv4 suspected, unconfirmed; it obsoletes the self-hosted UniFi controller job.

**User decisions (fixed):** keep self-hosted Headscale on worker.cloud; add a 3rd Nomad+Consul server on an Oracle node over the tailnet; public services = static sites, Ghost photo site, Immich, Mumble, mediashare, Jellyseerr (everything else tailnet/LAN-only); design works under today's IPv6-only WAN with a decision gate at UCG cutover; IaC = Ansible + Terraform.

## Target architecture

- **DNS**: two Pi-holes (hermes + zeus) via `external/pihole/` docker-compose + Ansible (off-cluster, like headscale — DNS must not depend on the cluster it boots). Dionysus Pi-hole demoted then retired. UCG DHCP hands out both. Headscale `dns.extra_records_path` serves `*.dbyte.xyz` → answered locally by every tailnet client from the netmap (no subnet route, no upstream needed); global nameservers become both Pi-holes at their **tailnet** IPs.
- **Subnet routing**: zeus becomes second subnet router; headscale ≥0.29 actively probes HA subnet routers and fails over (~15–30s) — fixes the exact "connected but not forwarding" outage mode.
- **Ingress**: public/private split via Traefik entrypoints — `websecure-proxied` loses `asDefault`; public services opt in by tag; private routers get an `internal-only` ipAllowList middleware; private names lose public DNS. After UCG frees port 8443 on zeus: Traefik becomes a `system` job on hermes+zeus (per-node ACME host volumes, DNS-01 duplicates are within LE limits), relay does passive nginx `backup` failover between them.
- **Cluster**: 3rd Consul+Nomad **server (no client)** on observability.cloud (not worker — keeps headscale-down and voter-down independent). All three advertise **tailnet IPs** (mixed addressing can't work; routing cloud→home via hermes's subnet route would put quorum behind hermes). Worst case headscale-down: cloud voter drops, home pair (direct LAN WireGuard, cached state) keeps 2/3 quorum.
- **Security**: Nomad gossip key + TLS + ACLs; Consul ACLs to default-deny; CA keys stay on zeus, never on the workstation; Traefik dashboard off insecure mode.
- **Backups**: app-level backups (vaultwarden sqlite, paperless export, headscale state) + nightly restic offsite to **Backblaze B2** (not OCI object storage — Oracle already hosts the voter, exit nodes, control plane, and relay; backups must be failure-independent of Oracle account reclaim. ~pennies/month. Optional free OCI second copy via `restic copy` later). Offline escape-hatch copy of 4–5 root secrets breaks the vaultwarden↔ansible-vault circle.
- **IaC**: `terraform/oci` (VCN, security lists tightened, instances imported with `prevent_destroy`) + `terraform/cloudflare` (records imported; per-name public records). State in OCI object storage S3-compat backend.
- **Monitoring**: Gatus gains per-server raft/leader checks, per-node liveness, backup-freshness heartbeats (POST-on-success), resolver checks; the dead-man's-switch heartbeat job is unpinned from hermes (asserts "cluster can schedule + reach out", per-node checks catch single-node loss). One-time: free external uptime check on the Gatus status page (who watches the watcher).

## Execution scope — this session

Per user instruction: **implement Phases 0, 1, and 2 now**; log Phases 3–8 as TaskNotes tasks (via the `task` CLI) with due dates and a recommended Claude model per task.

What "implement" means from this machine (repo work now, operational steps logged as tasks where they need accounts/hosts I can't reach):
- **Phase 0**: all repo edits + commits (one commit per logical change, single subject line). The `vault_headplane_cookie_secret` add needs the live Consul KV value + Bitwarden vault password — attempted; if the cluster/bw is unreachable from this sandbox, logged as a task with exact commands.
- **Phase 1**: all job specs / playbook / docs written and committed, with vaulted-secret placeholders documented. Creating the B2 account+bucket, running first backups, the restore test, the offline secret copy, and the post-verification dead-job cleanup are operational → logged as tasks.
- **Phase 2**: full Terraform code written (providers, import blocks, tightened security-list resources, backend config, README with bootstrap steps) + `.gitignore` entries so state/creds can't be committed. Running the state-bucket bootstrap, `terraform plan`/import, and the apply are operational → logged as tasks.

**Model recommendations for the remaining phases** (rationale: risk × judgment needed):
- Phase 3 (DNS layer) — **Opus 5**: multi-host migration with failure-mode reasoning, but well-specified here.
- Phase 4 (ingress split) — **Sonnet 5**: mechanical tag edits from an explicit list + verification.
- Phase 5 (third voter / raft surgery) — **Fable 5**: highest-blast-radius change in the plan; live quorum migration with per-step verification.
- Phase 6 (Nomad TLS/ACLs, Consul ACLs) — **Fable 5** (or Opus 5 if supervised closely): phased security rollout where a wrong step locks you out.
- Phase 7 (UCG cutover) — **Opus 5**: mostly human-driven physical/console work; the model assists with config edits and the decision gate.
- Phase 8 (monitoring) — **Sonnet 5**: config additions from a checklist.

## Phases

Two independent tracks until the UCG phase: **Track N** (network/DNS/ingress) and **Track C** (cluster/security/backups/IaC). Phase 1 (backups) must precede Phase 5 (raft surgery). Phase 2 (terraform: open UDP 41641) must precede Phase 5.

### Phase 0 — Hygiene (no runtime risk)
- Commit the uncommitted tailscale work as-is (`ansible/group_vars/tailscale.yaml`, `host_vars/{hermes,zeus}.yaml`, untracked `host_vars/worker.cloud.yaml`, `ansible/hosts`, `docs/Headscale.md`) — clean baseline for later reverts.
- Pin `external/headscale/docker-compose.yml` → `headscale/headscale:0.29.3`, drop `pull: always` for it (control plane on unpinned `:latest` is the scariest line in the repo; minor releases have one-way DB migrations). Pin traefik image in `jobs/traefik.hcl` (currently `latest` + force_pull).
- Pin `ansible/requirements.yml`; add `community.crypto`, `community.general`.
- Add missing `vault_headplane_cookie_secret` to vaulted `all.yaml` (pull live value from Consul KV `tailscale/headplane/secret`, don't regenerate).
- Fix `ansible/playbooks/gatus.yaml` curl|sh (copy the pipefail pattern from headscale.yaml).
- Traefik dashboard: remove `insecure = true` + the :8081 static port/entrypoint; add `api@internal` router on `traefik.dbyte.xyz`, private entrypoint only. Update the Gatus traefik-ping check accordingly.
- Replace hardcoded exit-node IP `100.64.0.7` with `tailscale_exit_node_use: "observability"` (hostname resolves from netmap; verify on one host first).

### Phase 1 — Backups before topology surgery (Track C)
- **Vaultwarden** (`jobs/vaultwarden/vaultwarden.hcl`): companion task in the same group (CSI volume is single-node-writer) — daily `sqlite3 .backup` + tar of attachments/sends/config/rsa keys → `/backups/vaultwarden` bind mount, keep 7, POST Gatus heartbeat on success.
- **Paperless** (`jobs/paperless/paperless.hcl`): companion task running `document_exporter` daily → `/backups/paperless`.
- **Headscale state** (`ansible/playbooks/headscale.yaml`): restic + systemd timer ON worker itself — sqlite `.backup` of db.sqlite + noise key + config → B2, straight over public internet (never via the tailnet it serves). Secrets in ansible-vault → root-only env file; never in Consul KV.
- **Offsite shipper**: new `jobs/backup/restic-offsite.hcl` periodic batch (05:00, after the existing 03–04:00 dumps), bind-mounts host `/backups` ro, `restic backup` → B2 S3 endpoint, `forget --keep-daily 14 --keep-weekly 8 --keep-monthly 6`, Sunday prune, monthly `check --read-data-subset=5%`, heartbeat POST on success. Secrets via existing Consul-KV template pattern (see `jobs/immich/immich-backup.hcl`). Verify immich-postgres-backup dumps land under the same `/backups` export; repoint if not.
- **Escape hatch** (one-time, manual): offline copy (paper/age-encrypted) of ansible vault password, restic passwords, B2 creds. New `docs/Disaster-Recovery.md` with restore order: headscale from B2 → tailnet → vaultwarden sqlite → vault-password.sh works → rest.
- **Cleanup after verified restore test**: delete dead `jobs/headscale/headscale.hcl` (live-runnable, would split-brain the control plane), `headscale-export.hcl`, `headscale-data.csi.hcl`; deregister old CSI volume.

### Phase 2 — Terraform (Track C)
- Layout: `terraform/oci/` + `terraform/cloudflare/` (two simple roots, no modules). State: OCI Object Storage S3-compat backend (manual bootstrap bucket + customer secret key, versioning on). Optional `terraform/ns1/` if the NS1 API key is handy; otherwise NS1 stays manual, noted.
- OCI: `import {}` blocks + `-generate-config-out`, hand-tidy. `prevent_destroy` on both instances. Tighten security lists (replace allow-all v4+v6): 22/tcp, 80/443/tcp, 64738 tcp+udp, **41641/udp (tailscale direct — required before Phase 5)**, ICMP/ICMPv6. Egress open. Create backup bucket (unused for now). Import reveals observability's shape → capacity gate for Phase 5 (if 1GB E2.1.Micro is too tight for consul+nomad servers, swap to always-free A1.Flex 1-OCPU/6GB — arm64 fine, it runs no workloads).
- Cloudflare: import existing records. **Verify the suspected `*.dbyte.xyz` wildcard A record**, then replace with per-name records at the relay IP for exactly the public set: `immich`, `request`, `share`, `mumble`, `headscale`, `headplane` .dbyte.xyz; the four vanity apexes + www; `photo`/`admin-photo`/apex james-hackett.ie; `pint.ing`. Private names → NXDOMAIN publicly. Keep wildcard DNS-01 certs (private hostnames stay out of CT logs).

### Phase 3 — DNS layer (Track N)
- **Two Pi-holes**: new `external/pihole/docker-compose.yml` (pinned image, 53 tcp/udp, web on 8053 — 80/8443 are Traefik's), `FTLCONF_dns_listeningMode=all`; new `ansible/playbooks/pihole.yaml` (headscale.yaml shape: docker, compose sync, firewall allowing 53 from LAN + 100.64.0.0/10, `DNSStubListener=no`), new `[pihole]` group = hermes+zeus, `group_vars/pihole.yaml` holds adlists/upstreams/static `.internal` records as data (one-time Teleporter seed from dionysus). Config-as-code, no gravity-sync/nebula-sync (UI becomes read-only by convention; nebula-sync is a drop-in later if that chafes).
- **Generator**: `scripts/sync-pihole-dns.sh` → `scripts/sync-dns.sh`, same `Host()` source of truth, three outputs: dnsmasq lines → both Pi-hole APIs; `extra-records.json` (A records → hermes/zeus **tailnet** IPs from the new `tailnet_ipv4` host_vars); static `.internal` records. Keep excluding headscale/headplane names. Wrapped in new `ansible/playbooks/dns.yaml`: generate locally, push to both Pi-holes, atomic copy of the JSON to `worker.cloud:/opt/headscale/data/extra-records.json` (headscale hot-reloads via fsnotify — write temp + rename; issue #2753).
- **Headscale config**: add `dns.extra_records_path` + change `dns.nameservers.global` to both Pi-hole tailnet IPs. NB: deployed config is seeded `force: false` (headplane edits in place) — hand-apply to `/opt/headscale/data/config.yaml` + restart container, mirror in repo copy.
- **Node resolv.conf**: each home node points at the *other* node's Pi-hole first, own second. Keep the `/etc/hosts` headscale pins.
- **Subnet router #2**: `tailscale_advertise_routes: "192.168.0.0/24"` on zeus (`accept_routes: false` already set), approve via headscale — **`approve-routes` replaces the full list**: automate in `ansible/playbooks/tailscale.yaml` post-play against `[headscale]`, always computing the union of desired routes across hosts (kills the documented footgun). Test failover from the LAN only (never restart tailscaled over the tailnet): stop tailscaled on hermes, roaming client must reach 192.168.0.5 via zeus in ~15–30s.
- **Dionysus Pi-hole**: tertiary in DHCP during 1–2 week soak → remove → shut down. Update `jobs/pihole-backup.hcl` to loop over both new instances (`:8053/api/teleporter`, now password-protected).

**Shipped 2026-09-08** (branch `phase3-redundant-pihole-split-dns`); runbook in `docs/DNS.md`. Deviations from the above, each deliberate:
- **No general host firewall.** `INPUT` policy on both home nodes is `ACCEPT` with no rules, and there is no public IPv4 — adding one is a change with its own blast radius and belongs to its own phase. What did ship is narrower and load-bearing: a port-53-only ruleset (`/opt/pihole/dns-firewall.sh` + systemd unit ordered after docker and tailscaled) because the DS-Lite line gives br0 a globally routable IPv6 address and FTL binds the wildcard, i.e. without it this is an open resolver the moment the router's inbound policy changes.
- **`tailscale_accept_dns: false` added on hermes and zeus** — not in the plan, and required. A node whose resolution comes from MagicDNS whose upstream is that node's own Pi-hole is a loop, and tailscaled would overwrite the static `/etc/resolv.conf` the playbook writes. That costs `*.ts.dbyte.xyz` resolution on those nodes, which the `observability.ts.dbyte.xyz` heartbeats in `jobs/` depend on, so the Pi-holes now carry static records for every inventory host's MagicDNS name (generated from `tailnet_ipv4`) plus `server=/ts.dbyte.xyz/100.100.100.100` for anything else.
- **`server=/consul/127.0.0.1#8600` is emitted by `sync-dns.sh`.** Disabling the resolved stub listener removes how `.consul` resolved for both the host and every container (docker daemon `dns` is 172.17.0.1). It has to live in `dnsmasq_lines` because that array is replaced wholesale on every apply.
- **Static `.internal` records stayed in `group_vars/pihole.yaml`, not in the generator.** They are not derived from `Host()` rules, and two owners for one setting is how drift starts.
- **`pihole_fallback_resolvers` keeps dionysus as each node's third resolver** through the soak, which also removes the bootstrap gap: during the first rollout the node whose Pi-hole does not exist yet still resolves.
- Nodes have 16GB, not the 8GB the risk list assumes — the headroom concern does not apply.

- **`dns.nameservers.global` stays exactly the two Pi-holes** (decision 2026-09-09, after a live outage during the build: the home link dropped and the laptop lost *all* DNS, public names included, because MagicDNS's only global nameserver was 192.168.0.5 behind hermes's subnet route). A public third entry was considered and rejected in favour of a documented break-glass in `docs/DNS.md` — `tailscale set --accept-dns=false` on the client, or a hand-added resolver on worker — so nothing standing bypasses the blocker.

- **IPv6 is the only native transit at home** (established 2026-09-09): Virgin Media runs the line as DS-Lite with the IPv4-in-IPv6 tunnel disabled on their side, so the only IPv4 egress is via a tailscale exit node. That makes the chain `native IPv6 → headscale → tailnet → exit node → IPv4` one-directional, and the IPv6 `/etc/hosts` pin for headscale load-bearing rather than belt-and-braces. Consequences: never disable IPv6 on hermes/zeus to work around a v6 fault; the router must advertise SLAAC (stateful DHCPv6 clears the autonomous flag and the nodes, which run no DHCPv6 client, lose their address while keeping the RA default route); and the hardcoded Oracle VCN AAAA in `pihole_headscale_pins` must be updated before it ever changes. Phase 7's UCG cutover is what ends this dependency.

Still to do at cutover: point DHCP at 192.168.0.4/.3, seed the Teleporter export from dionysus, hand-apply the `dns:` block to `worker.cloud:/opt/headscale/data/config.yaml` (headplane edits it in place, so the repo copy is not deployed), and put `vault_pihole_password` in the vault and Consul KV `pihole/password`.

### Phase 4 — Ingress split (Track N)
- `jobs/traefik.hcl`: remove `asDefault = true` from `websecure-proxied` (keep on `websecure`); add `internal-only` ipAllowList middleware to the file provider (`127.0.0.1/32, 192.168.0.0/24, 100.64.0.0/10, fd7a:115c:a1e0::/48`) — never attach it to relay-facing routers (PROXY protocol = real public IPs).
- Public jobs add `traefik.http.routers.<name>.entrypoints=websecure,websecure-proxied`: `jobs/web/{website,ihatenixos,crazybitta,nicecocks,pinting,mediabrowse}.hcl`, `jobs/photo-site/photo.hcl` (both routers incl. photo-analytics), `jobs/immich/immich.hcl`, `jobs/jellyseerr.hcl`. Mumble already explicit. File-provider `photo-activitypub`/`photo-wellknown` → both entrypoints; `synodrive`/`video` → `internal-only`.
- Private jobs (vaultwarden, paperless, actual-budget, home-assistant, molecule, gerry) add `middlewares=internal-only@file`. **Verify gerry receives no inbound webhooks** (nothing in-repo suggests it; check the gerry source) — if it does, it moves to the public list.
- Gatus `apps` group: private names lose public DNS; observability is a tailnet member so checks resolve via extra_records → verify the Gatus container inherits tailnet DNS, else pin those endpoints to the Traefik tailnet IP with a Host header. Deliberate improvement: checks now exercise the path real private clients use.

### Phase 5 — Third server over the tailnet (Track C; needs Phases 1+2)
- Voter on **observability.cloud**, Consul server AND Nomad server, **no Nomad client** (`nomad_client_enabled: false` host var gates client config/docker/host-volume tasks in `configure-nomad-consul.yaml`). `non_voting_server` is Enterprise-only and unwanted anyway.
- Addressing: new `tailnet_ipv4` host_var per node = single source of truth. Consul `bind_addr` → `GetInterfaceIP "tailscale0"`; Nomad `advertise{}` → `{{ tailnet_ipv4 }}`; `retry_join` lists built from host_vars (IPs, not names — no DNS dependency at daemon start). Nomad client `network_interface` pinned to the LAN interface so allocation/service addresses stay LAN (Traefik/consul catalog unaffected; node-level `.node.consul` answers become 100.64/10 — nothing may depend on those).
- Harden the new coupling: `Wants/After=tailscaled.service` + wait-for-tailscale-IP `ExecStartPre` in both service units; doc + comment: tailscaled restarts on cluster members are one-node-at-a-time over LAN/public SSH only (management paths already avoid the tailnet).
- Migration (each step verified via `consul operator raft list-peers` / `nomad operator raft list-peers`): add observability to `[nomad]` (keep zeus first / set explicit `consul_ca_host: zeus`); `bootstrap_expect: 3` in the same rollout (inert for nodes with existing raft state, prevents fresh split-brain); make repo/playbooks arch-aware (cloud node may be arm64); roll zeus → verify → roll hermes → verify → join observability as third voter; confirm `nomad node status` still shows only hermes+zeus as clients.
- Rollback: revert to LAN advertise + expect 2, restart home pair one at a time, stop cloud daemons, `raft remove-peer` if autopilot doesn't reap.
- Circular-dependency reasoning (documented in docs/): headscale down → cloud voter may drop (DERP decay per the August outage) → home pair keeps 2/3 quorum on direct LAN WireGuard with cached state. Voter on worker would correlate headscale-down with voter-down — that's why it's on observability.

### Phase 6 — Cluster security (Track C)
Order: gossip key → TLS → Nomad ACLs → Consul ACLs. Each step independently revertible.
- Nomad gossip `encrypt` key (verified absent): one-shot all-three-servers restart window.
- Fix CA handling both stacks: stop fetching the Consul CA **private key** to the workstation (`configure-nomad-consul.yaml` fetch loop); play-scoped tempfile + `always:` cleanup; shred `/tmp/consul-tls` once. New Nomad CA via `nomad tls ca create` on zeus; CA keys live root-only on zeus.
- Nomad TLS rollout via `rpc_upgrade_mode` (servers accept mixed → clients TLS → servers strict + HTTPS); update `NOMAD_ADDR`/`NOMAD_CACERT`, scripts, Gatus checks.
- Nomad ACLs: enable, bootstrap, management token → vaultwarden + offline copy; **no anonymous policy (default deny)**; one operator token vaulted for automation.
- Consul ACLs: enable with `default_policy=allow` → bootstrap → node-identity agent tokens → `nomad-agent` token (service/node write, **key_prefix read** — keeps every existing `{{ key }}` template working) → Traefik consulCatalog read token via KV → anonymous policy gets node/service read (keeps `.consul` DNS + Pi-hole forwarding working) → flip to `default_policy=deny` → verify DNS, Traefik, a KV-templated alloc restart, backups.

### Phase 7 — UCG cutover (external dependency: install after 2026-09-12)
1. Export self-hosted controller backup FIRST; adopt/import into the UCG. DHCP: DNS = 192.168.0.4 + .3 (+ .5 during soak), static leases, disable UCG DNS interception/ad-block (Pi-hole is the resolver of record).
2. Retire `jobs/unifi/unifi.hcl` → `jobs/archive/`; deregister `unifi`/`unifi-mongo` CSI volumes after UCG confirmed; remove `unifi.dbyte.xyz` records; `insecure@file` serversTransport loses its consumer (keep only if proxying the UCG UI).
3. **Port 8443 on zeus now free → dual Traefik**: `jobs/traefik.hcl` → `type = "system"` + constraint `${attr.unique.hostname}` regexp `hermes|zeus` (belt-and-braces vs future cloud clients); ACME moves from ephemeral_disk to a per-node host volume (per-node stores — Traefik CE can't share ACME; two DNS-01 issuers of the same wildcards is within LE duplicate limits); relay `stream.conf.j2` gets `upstream` blocks: hermes primary, `zeus backup` (`max_fails=2 fail_timeout=10s`; verified supported in stream module). `sync-dns.sh` emits both node IPs for internal + tailnet records. No keepalived — relay covers public failover, dual A records cover internal; add keepalived later only if some LAN client handles multi-A badly.
4. **Decision gate — probe the UCG WAN address externally**:
   - **Public IPv4 → home becomes primary ingress** (firm recommendation): UCG port-forwards 80/443/64738 → hermes; direct traffic arrives on `websecure` with real source IPs (no PROXY protocol needed); public per-name records flip to home IP, TTL 120s, grey-cloud (Mumble is L4 — cannot orange-cloud). Rationale: Irish users currently detour via Oracle London (~25–35ms + WG overhead + shape bandwidth cap); the relay path chains observability ∧ tailnet ∧ home ∧ Traefik and the tailnet layer is the least reliable link per the two 2026 outages. Relay stays warm standby; failover = `scripts/failover-ingress.sh` flipping records via Cloudflare API (creds already in Consul KV; ddclient job is prior art), triggered manually off Gatus alerts; ~2–5 min budget. If the Blacknight IP proves dynamic, add a ddclient-style updater or stay relay-primary until lease stability is observed.
   - **Still CGNAT → relay stays primary**; everything else already stands alone. No second relay (Caddy owns 80/443 on worker); revisit only if single-relay availability actually hurts.
5. Revert the TEMPORARY exit-node hack once home IPv4 exists: hermes re-advertises (`tailscale_exit_node: true`, drop `exit_node_use` on hermes+zeus), re-approve hermes routes with the **full** list (`192.168.0.0/24,0.0.0.0/0,::/0`).

### Phase 8 — Monitoring consolidation
In `external/gatus/config.yaml` (+ playbook rerun):
- Per-server: `GET :8500/v1/status/leader` (unauthenticated even under deny) `[BODY] != ""` + TCP :4647, all three servers over tailnet. Per-node liveness (TCP/ICMP) for hermes+zeus.
- Unpin `jobs/gatus-heartbeat.hcl` from hermes — dead-man's-switch asserts "cluster schedules + reaches out"; per-node checks catch single-node loss; both-down still trips it.
- Backup freshness: three `external-endpoints` with `heartbeat.interval: 26h` (`backups_offsite`, `backups_vaultwarden`, `backups_headscale` — the last posted over the public internet from worker). POST-on-success only; no restic-polling from Gatus.
- DNS checks against both Pi-holes (tailnet IPs), HTTP per Traefik node once dual.
- One-time manual: free external uptime check (UptimeRobot/healthchecks.io) on the public Gatus page — observability now carries alerting *and* a voter. Document in docs/.
- Update docs: new cluster-topology section, DNS architecture, DR runbook cross-links; retire stale `br0` references.

## Key files

| Area | Files |
|---|---|
| Cluster templates | `ansible/playbooks/templates/{consul/consul.hcl.j2,consul/consul.service,nomad/nomad-base.hcl.j2,nomad/nomad-server.hcl.j2,nomad/nomad-client.hcl.j2,nomad/nomad.service}`, `ansible/playbooks/configure-nomad-consul.yaml` |
| Inventory/vars | `ansible/hosts`, `ansible/group_vars/{all,tailscale,pihole(new)}.yaml`, `ansible/host_vars/*.yaml` (new `tailnet_ipv4`, `nomad_client_enabled`) |
| DNS | `external/pihole/` (new), `ansible/playbooks/{pihole,dns}.yaml` (new), `scripts/sync-dns.sh` (replaces sync-pihole-dns.sh), `external/headscale/config.yaml` |
| Ingress | `jobs/traefik.hcl`, per-job tag edits (public list above), `ansible/playbooks/templates/relay/stream.conf.j2`, `ansible/group_vars/relay.yaml` |
| Backups | `jobs/vaultwarden/vaultwarden.hcl`, `jobs/paperless/paperless.hcl`, `jobs/backup/restic-offsite.hcl` (new), `ansible/playbooks/headscale.yaml`, `docs/Disaster-Recovery.md` (new) |
| Terraform | `terraform/{oci,cloudflare}/` (new) |
| Monitoring | `external/gatus/config.yaml`, `jobs/gatus-heartbeat.hcl` |

## Verification (per phase, end-to-end)

- **Backups**: run each job once manually (`nomad job dispatch` / systemd `start`), `restic snapshots` shows all three sources, then a full test restore of vaultwarden sqlite + headscale db to a scratch dir; Gatus heartbeats green.
- **Terraform**: `terraform plan` clean after import (no-op); external port probe confirms only the intended ports answer on both Oracle IPs.
- **DNS**: `dig vault.dbyte.xyz @192.168.0.4` and `@192.168.0.3` (LAN answers); `tailscale dns query vault.dbyte.xyz` from a roaming client (extra_records answer, no subnet route); ad domain returns blocked from both; stop tailscaled on hermes (from LAN!) → roaming client still resolves + reaches 192.168.0.5 via zeus; Gatus `internal` stays green during that test.
- **Ingress split**: from an external network, private names NXDOMAIN + direct-IP requests with private Host headers get 4xx from the relay path; public list still serves; from tailnet, everything serves.
- **Quorum**: `raft list-peers` ×2 show 3 voters; stop consul+nomad on any one node → cluster still schedules a test job; restart tailscaled on observability → voter rejoins.
- **Security**: unauthenticated `nomad status` fails; with token succeeds over TLS; `dig @consul` still answers; a KV-templated alloc restarts cleanly under deny.
- **UCG gate**: external probe of home WAN; after flip, `mtr`/curl timing from an external Irish vantage vs the relay path; kill Traefik on hermes → relay serves via zeus within `fail_timeout`.

## Risks / assumptions (surfaced deliberately)

- **B2 introduces a tiny paid dependency** (~pennies/mo) — chosen over OCI object storage for failure independence from the Oracle account that now hosts the voter, relay, control plane, and exit nodes. Swap to an OCI bucket if unacceptable, accepting correlated loss.
- Observability's shape is unknown until the terraform import; if 1GB E2.1.Micro, consul+nomad servers fit but tight (`GOMEMLIMIT`); escape valve = always-free A1.Flex swap.
- `*.dbyte.xyz` wildcard A record in Cloudflare is inferred (Gatus reaches vault.dbyte.xyz publicly), not verified — confirm before Phase 4's DNS step.
- Gerry inbound-webhook question — confirm against the gerry source before leaving it private.
- Headplane edits the deployed headscale config in place; repo copy ≠ deployed copy — every dns-block change is a hands-on edit + restart on worker.
- Cluster health now rides tailscale0 on all three nodes: the never-restart-tailscaled-over-the-tailnet rule becomes a quorum rule; mitigated by systemd ordering, LAN/public management paths, and docs.
- The two home nodes are 8GB and near capacity; this plan adds ~250MB/node (Pi-hole + second Traefik) and nothing heavier — recheck headroom after commit 07daeb2's right-sizing.
- Pi-hole UI becomes config-as-code read-only by convention; drift is possible if UI edits happen — nebula-sync is the drop-in if that workflow is wanted.
