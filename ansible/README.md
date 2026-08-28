---
title: Ansible
---

# Ansible

## Description

This repository contains a collection of Ansible playbooks and roles that I use to manage my personal infrastructure.

## Usage

Run all commands from the **repository root** — `ansible.cfg` lives there and is
auto-discovered, so there's no need to `cd` into `ansible/`.

### `apt-update.yaml`

| Variable            | Description                                | Default |
| ------------------- | ------------------------------------------ | ------- |
| `upgrade`           | upgrade packages                           | `false` |
| `packages`          | install packages                           | `[]`    |
| `check_hashicorp`   | check if hashicorp packages can be updated | `false` |
| `upgrade_hashicorp` | upgrade hashicorp packages                 | `false` |

#### Example

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/apt-update.yaml
```

### `bootstrap.yaml`

Adds users, sets up the base system, and installs Hashicorp (Nomad, Consul) and Docker on all `[nomad]` hosts.

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/bootstrap.yaml
```

### `tailscale.yaml`

Installs Tailscale and connects the node to headscale. Targets the `[tailscale]` group.

Uses the `artis3n.tailscale` collection — install it once before first use:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

#### Variables

| Variable                   | Description                                        | Default                         |
| -------------------------- | -------------------------------------------------- | ------------------------------- |
| `tailscale_login_server`   | Headscale (or Tailscale control plane) URL         | `https://headscale.dbyte.xyz`   |
| `tailscale_advertise_routes` | Subnet routes to advertise (empty = none)        | `""`                            |
| `tailscale_exit_node`      | Advertise this node as an exit node                | `false`                         |
| `vault_tailscale_authkey`  | Pre-auth key (ansible-vault encrypted, in all.yaml)| —                               |

`tailscale_advertise_routes` and `tailscale_exit_node` are per-host — override them in `host_vars/<host>.yaml`.

These three vars are composed into `tailscale_args` (the collection's variable) automatically in `group_vars/tailscale.yaml`. You don't need to set `tailscale_args` directly.

To skip reconnecting nodes that are already up (e.g. in a broader config run):

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/tailscale.yaml -e '{"tailscale_up_skip": true}'
```

Note: the boolean must be passed as JSON — `-e tailscale_up_skip=true` passes a string and the role's conditional will fail.

#### Example

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/tailscale.yaml
```

### `configure-nomad-consul.yaml`

Deploys Nomad and Consul config files, systemd service units, and host volume

directories. Safe to re-run — only restarts services if config actually changed.

Requires `vault_consul_encrypt_key` to be set (use ansible-vault):

```bash
ansible-vault encrypt_string 'your-key-here' --name vault_consul_encrypt_key >> ansible/group_vars/all.yaml
```

The vault password is fetched automatically from Bitwarden via `vault-password.sh`.

Store the vault password in Bitwarden as an item named **`ansible-vault`**, then run:

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/configure-nomad-consul.yaml
```

If your Bitwarden vault is locked, the script will prompt for your master password once.

You can also pre-unlock and export the session to avoid the prompt:

```bash
export BW_SESSION=$(bw unlock --raw)
ansible-playbook -i ansible/hosts ansible/playbooks/configure-nomad-consul.yaml
```

### `relay.yaml`

Deploys the off-site L4 ingress relay to the `[relay]` group.

Home broadband is DS-Lite, so the router has no public IPv4 and inbound
connections cannot be forwarded to the LAN at all. The relays hold the public
IPv4 that DNS points at and pass TCP/UDP through to Traefik on hermes over the
tailnet. TLS is still terminated on hermes, so certificates and ACME are
untouched.

HTTPS carries a PROXY protocol header into Traefik's `websecure-proxied`
entrypoint (`:8443`) so the real client address survives the extra hop. HTTP and
Mumble pass through unwrapped.

#### Variables

| Variable                    | Description                                        | Default          |
| --------------------------- | -------------------------------------------------- | ---------------- |
| `relay_upstream_node`       | Tailnet node running Traefik                       | `hermes`         |
| `relay_upstream_ip`         | Upstream tailnet IPv4; empty = discover at runtime | `""`             |
| `relay_upstream_https_port` | Traefik PROXY-protocol entrypoint                  | `8443`           |
| `relay_upstream_http_port`  | Traefik plain HTTP entrypoint                      | `80`             |
| `relay_upstream_voice_port` | Mumble TCP+UDP port                                | `64738`          |
| `relay_tailnet_cidr`        | Range Traefik trusts PROXY headers from            | `100.64.0.0/10`  |

#### Before first run

The Oracle VCN security list (or NSG) must allow ingress on `80/tcp`,
`443/tcp` and `64738` tcp+udp. Oracle's cloud firewall is separate from the host
firewall this playbook configures, and traffic must pass both.

#### Example

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/relay.yaml
```

### `headscale.yaml`

Deploys the headscale + headplane control plane to the `[headscale]` group, as a
Docker Compose stack with Caddy terminating TLS.

It runs off-cluster on purpose. Previously it was a Nomad job on hermes behind
Traefik, which meant reaching it required a working tailnet *and* a working home
connection — when the home line moved to DS-Lite and lost its public IPv4, every
node was stranded with no way to re-register. See [docs/Headscale.md](../docs/Headscale.md).

#### Variables

| Variable                        | Description                             | Default          |
| ------------------------------- | --------------------------------------- | ---------------- |
| `headscale_deploy_dir`          | Deploy directory on the host            | `/opt/headscale` |
| `vault_headplane_cookie_secret` | headplane session secret (ansible-vault) | —                |

#### Before first run

`headscale.dbyte.xyz` and `headplane.dbyte.xyz` must already resolve to the host
— Caddy issues certificates over HTTP-01 and fails otherwise — and state must be
migrated from the old CSI volume. The playbook refuses to start without it.

#### Example

```bash
ansible-playbook -i ansible/hosts ansible/playbooks/headscale.yaml
```
