#!/bin/sh
# Runs opentofu in one of the roots with credentials injected from Vaultwarden,
# so no secret ever lands in a tfvars or backend file.
#
# usage: ./tf.sh <oci|cloudflare|ns1> <terraform args...>
#
# Reads custom fields from the "terraform-homelab" Vaultwarden item:
#   state_access_key / state_secret_key  - OCI customer secret key (S3 state backend)
#   cloudflare_api_token                 - Zone.DNS edit token
#   ns1_api_key                          - same key as Consul KV ns1/key
# OCI provider auth is not in Vaultwarden: it uses ~/.oci/config (`oci setup config`).
#
# Everything this needs is per-machine and git-ignored, so a fresh laptop fails
# in several different places at once. The preflight below names each missing
# piece and the command that fixes it, rather than letting a provider report it
# as an authentication error three steps later.
set -eu

usage() {
    echo "usage: $0 <oci|cloudflare|ns1> <terraform args...>" >&2
    exit 2
}

[ $# -ge 1 ] || usage

root=$1
shift

case "$root" in
    oci | cloudflare | ns1) ;;
    *) usage ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root_dir="$script_dir/$root"

missing=""
note() { missing="$missing  - $1
"; }

command -v tofu >/dev/null 2>&1 || note "opentofu is not installed: brew install opentofu"
command -v jq >/dev/null 2>&1 || note "jq is not installed: brew install jq"
command -v bw >/dev/null 2>&1 || note "the Bitwarden CLI is not installed: brew install bitwarden-cli"

[ -f "$root_dir/backend.conf" ] ||
    note "$root/backend.conf is missing: cp $root/backend.conf.example $root/backend.conf and fill in the Object Storage namespace"

if [ -f "$root_dir/terraform.tfvars.example" ] && [ ! -f "$root_dir/terraform.tfvars" ]; then
    note "$root/terraform.tfvars is missing: cp $root/terraform.tfvars.example $root/terraform.tfvars and fill in the OCIDs / record ids"
fi

if [ "$root" = "oci" ] && [ ! -f "$HOME/.oci/config" ]; then
    note "$HOME/.oci/config is missing: brew install oci-cli && oci setup config (the DEFAULT profile supplies the oci provider's tenancy, user, fingerprint and key)"
fi

if [ -n "$missing" ]; then
    echo "Cannot run tofu in $root — set up is incomplete:" >&2
    printf '%s' "$missing" >&2
    echo "See terraform/README.md for the one-time bootstrap." >&2
    exit 1
fi

if [ -z "${BW_SESSION:-}" ]; then
    BW_SESSION=$(bw unlock --raw)
    export BW_SESSION
fi

if ! item_json=$(bw get item terraform-homelab 2>/dev/null); then
    echo "error: no 'terraform-homelab' item in Vaultwarden (or the vault is stale — try 'bw sync')." >&2
    exit 1
fi

field() {
    value=$(printf '%s' "$item_json" | jq -r --arg name "$1" \
        '(.fields // [])[] | select(.name == $name) | .value')
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "error: the terraform-homelab item has no '$1' custom field — see terraform/README.md." >&2
        exit 1
    fi
    printf '%s' "$value"
}

AWS_ACCESS_KEY_ID=$(field state_access_key)
AWS_SECRET_ACCESS_KEY=$(field state_secret_key)
CLOUDFLARE_API_TOKEN=$(field cloudflare_api_token)
NS1_APIKEY=$(field ns1_api_key)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY CLOUDFLARE_API_TOKEN NS1_APIKEY

cd "$root_dir"

# init picks up the non-secret backend settings automatically
if [ "${1:-}" = "init" ]; then
    set -- "$@" -backend-config=backend.conf
fi

exec tofu "$@"
