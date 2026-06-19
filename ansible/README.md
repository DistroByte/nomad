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
