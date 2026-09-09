# OpenTofu

Two independent roots — this is 2 VMs and some DNS records, deliberately not
an enterprise layout:

- `oci/` — the Oracle Cloud VCN, security rules, both instances, and the
  backup/state buckets.
- `cloudflare/` — DNS records for the Cloudflare-hosted public zones.
- `ns1/` — the NS1-hosted zone (`pint.ing`).

State lives in OCI Object Storage via its S3-compatible API (versioned bucket),
so it is not tied to one laptop. No HCP.

## Credentials — one Vaultwarden item, injected at runtime

No secret ever lives in a tfvars or backend file. `./tf.sh <root> <args>`
unlocks Bitwarden (reusing `$BW_SESSION` if set), reads the custom fields off
the **terraform-homelab** item, exports them as the env vars every provider
and the state backend natively read, and execs `tofu` in the chosen root:

| Vaultwarden field | Becomes | Used by |
|---|---|---|
| `state_access_key` | `AWS_ACCESS_KEY_ID` | S3 state backend (all roots) |
| `state_secret_key` | `AWS_SECRET_ACCESS_KEY` | S3 state backend (all roots) |
| `cloudflare_api_token` | `CLOUDFLARE_API_TOKEN` | cloudflare provider |
| `ns1_api_key` | `NS1_APIKEY` | ns1 provider |

OCI provider auth is the exception: it reads `~/.oci/config` (written by
`oci setup config`), the same file the OCI CLI uses — tenancy, user,
fingerprint, key path and region all come from the DEFAULT profile there, and
identifying OCIDs stay out of this public repo.

What remains on disk per root is non-secret but identifying, so still
git-ignored: `backend.conf` (bucket/region/namespace endpoint — `tf.sh`
passes it to `init` automatically) and `terraform.tfvars` (resource OCIDs for
import, record ids).

`tf.sh` refuses to run until that is all in place, and says which piece is
missing and the command that fixes it — everything it needs is per-machine and
git-ignored, so a fresh laptop is missing several things at once and a provider
would otherwise report it as an authentication error three steps later:

```
$ ./tf.sh oci plan
Cannot run tofu in oci — set up is incomplete:
  - oci/backend.conf is missing: cp oci/backend.conf.example oci/backend.conf and fill in the Object Storage namespace
  - oci/terraform.tfvars is missing: cp oci/terraform.tfvars.example oci/terraform.tfvars and fill in the OCIDs / record ids
  - /Users/you/.oci/config is missing: brew install oci-cli && oci setup config
```

## One-time bootstrap (manual, in the OCI console)

1. Create bucket `terraform-state` in the home region, **enable versioning**.
2. Create a Customer Secret Key for your user (Identity → your user →
   Customer secret keys) — store the pair as `state_access_key` /
   `state_secret_key` on the terraform-homelab Vaultwarden item, alongside
   `cloudflare_api_token` and `ns1_api_key` (the latter matches Consul KV
   `ns1/key`).
3. Run `oci setup config` if `~/.oci/config` does not exist yet.
4. Copy `backend.conf.example` → `backend.conf` in each root, fill in the
   namespace.
5. `./tf.sh <root> init` in each root.

## OCI import workflow

1. Copy `terraform.tfvars.example` → `terraform.tfvars` (git-ignored), fill in
   the OCIDs (console → Networking / Compute); provider auth comes from ~/.oci/config.
2. `./tf.sh oci plan -generate-config-out=generated.tf` — the `import {}` blocks
   in `imports.tf` pull the VCN, subnet, internet gateway, route table and both
   instances into generated config.
3. Hand-tidy `generated.tf` into `network.tf`/`instances.tf`; keep
   `prevent_destroy` on both instances (a wrong apply must never be able to
   recreate the box holding headscale's state) and add
   `ignore_changes = [source_details, defined_tags]` if the plan demands.
4. `./tf.sh oci plan` until it is a no-op, then commit the tidied config.
5. The **security rules are the one deliberate change**: `security.tf` adopts
   the VCN's default security list and replaces today's allow-all with the
   tightened rule set. Review the plan diff, apply, then verify from outside:
   only 22, 80, 443, 64738 and 41641/udp should answer, and tailscale should
   report a direct (non-DERP) path between home and cloud nodes.
   **Do this before adding the third Nomad/Consul server** — cluster traffic
   over the tailnet needs the 41641/udp rule or it silently falls back to DERP.

While importing, note the shape of `observability` (E2.1.Micro 1GB vs A1
Flex): it gates whether the third Nomad/Consul server fits there or the
instance should be swapped for an always-free A1.Flex 1-OCPU/6GB first.

## Cloudflare import workflow

1. Create a scoped API token (Zone.DNS edit on the relevant zones) and store
   it as `cloudflare_api_token` on the terraform-homelab Vaultwarden item.
2. Existing records are imported rather than recreated: use
   [`cf-terraforming`](https://github.com/cloudflare/cf-terraforming)
   (`cf-terraforming generate --resource-type cloudflare_dns_record --zone <id>`
   and matching `import` output) per zone, tidy into `records.tf`.
3. Today `*.dbyte.xyz` is a CNAME to the apex, whose A record is the relay —
   which is why every private service name resolves publicly. The per-name
   public record set replacing it is described in `records-phase4.tf.example`;
   **do not apply it until the Traefik entrypoint split (plan Phase 4) has
   shipped**, or private services become unreachable for clients that rely on
   public DNS while still being routable.

## NS1 import workflow

The estate is one zone with one A record, fully asserted in `ns1/records.tf`
with `import` blocks already in place (NS1 record import ids are just
`zone/domain/type`, no opaque ids to look up). With the key on the Vaultwarden
item, `./tf.sh ns1 init && ./tf.sh ns1 plan` should show two imports and no
changes. The apex A record points at
`var.relay_ipv4`, so the UCG-cutover ingress flip is a one-variable change
applied across the cloudflare and ns1 roots together.
