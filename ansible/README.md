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

### `install-hashicorp.yaml`

#### Example

```bash
ansible-playbook -i hosts playbooks/install-hashicorp.yaml
```
