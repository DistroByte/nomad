#!/bin/sh
# Deploys the Docker Compose projects in this directory to dionysus (Synology
# DSM) at /etc/docker-compose/<project>/ and brings each one up. The repo is the
# source of truth: edit the file here and rerun, don't edit on the NAS.
#
# A script rather than an Ansible playbook because ansible-core needs Python
# 3.9+ on the target and DSM ships 3.8. Root SSH because DSM gives other admin
# accounts no passwordless sudo.
#
# `docker compose up -d` only recreates a container whose resolved config
# changed, so rerunning is safe for pihole, which serves the LAN's DNS. It does
# not pull: to update an image, pin a newer tag or pull on the host first.
#
# Usage:
#   external/dionysus/deploy.sh            # every project
#   external/dionysus/deploy.sh arr pihole # just these
set -eu

host=${DIONYSUS_HOST:-root@192.168.0.5}
# ~/.ssh/config pins the 1Password agent; the homelab key is in Bitwarden's.
agent=${DIONYSUS_SSH_AGENT:-$HOME/.bitwarden-ssh-agent.sock}
root=/etc/docker-compose
# Container Manager's CLI is not on root's non-interactive PATH.
docker=/usr/local/bin/docker
here=$(cd "$(dirname "$0")" && pwd)

if [ "$#" -eq 0 ]; then
	for dir in "$here"/*/; do
		set -- "$@" "$(basename "$dir")"
	done
fi

for project in "$@"; do
	file="$here/$project/docker-compose.yaml"
	if [ ! -f "$file" ]; then
		echo "no compose file for $project at $file" >&2
		exit 1
	fi
	echo "== $project"
	ssh -o IdentityAgent="$agent" "$host" "cat $root/$project/docker-compose.yaml 2>/dev/null" |
		diff -u --label "dionysus:$project" --label "repo:$project" - "$file" || true
	ssh -o IdentityAgent="$agent" "$host" \
		"mkdir -p $root/$project && cat > $root/$project/docker-compose.yaml && cd $root/$project && $docker compose up -d --remove-orphans" <"$file"
done
