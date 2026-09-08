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
set -eu

root=$1
shift

if [ -z "${BW_SESSION:-}" ]; then
    BW_SESSION=$(bw unlock --raw)
    export BW_SESSION
fi

item_json=$(bw get item terraform-homelab)
field() {
    printf '%s' "$item_json" |
        jq -er --arg name "$1" '.fields[] | select(.name == $name) | .value'
}

AWS_ACCESS_KEY_ID=$(field state_access_key)
AWS_SECRET_ACCESS_KEY=$(field state_secret_key)
CLOUDFLARE_API_TOKEN=$(field cloudflare_api_token)
NS1_APIKEY=$(field ns1_api_key)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY CLOUDFLARE_API_TOKEN NS1_APIKEY

cd "$(dirname "$0")/$root"

# init picks up the non-secret backend settings automatically
if [ "${1:-}" = "init" ] && [ -f backend.conf ]; then
    set -- "$@" -backend-config=backend.conf
fi

exec tofu "$@"
