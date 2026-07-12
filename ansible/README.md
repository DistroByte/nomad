---
title: Ansible
created: 2023-12-17, 3:07:14 am
---

# Ansible

## Description

This repository contains a collection of Ansible playbooks and roles that I use to manage my personal infrastructure.

## Usage

### `apt-update.yaml`

| Variable            | Description                                | Default |
| ------------------- | ------------------------------------------ | ------- |
| `upgrade`           | upgrade packages                           | `false` |
| `packages`          | install packages                           | `[]`    |
| `check_hashicorp`   | check if hashicorp packages can be updated | `false` |
| `upgrade_hashicorp` | upgrade hashicorp packages                 | `false` |

#### Example

```bash
ansible-playbook -i hosts playbooks/apt-update.yaml
```

### `bootstrap.yaml`

Adds users, sets up the base system, and installs Hashicorp (Nomad, Consul) and Docker on all `[nomad]` hosts.

```bash
ansible-playbook -i hosts playbooks/bootstrap.yaml
```

### `tailscale.yaml`

Installs Tailscale and connects the node to headscale. Targets the `[tailscale]` group.
Uses the `artis3n.tailscale` collection — install it once before first use:

```bash
ansible-galaxy collection install -r requirements.yml
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
ansible-playbook -i hosts playbooks/tailscale.yaml -e tailscale_up_skip=true
```

#### Example

```bash
ansible-playbook -i hosts playbooks/tailscale.yaml
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
