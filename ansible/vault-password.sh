#!/bin/sh
# Fetches the Ansible vault password from Bitwarden.
# Requires bw CLI to be logged in (run `bw login` once if not).
# If BW_SESSION is not set, prompts for the Bitwarden master password to unlock.
set -e

if [ -z "$BW_SESSION" ]; then
    BW_SESSION=$(bw unlock --raw)
fi

bw get password "Nomad Ansible Vault Key" --session "$BW_SESSION"
