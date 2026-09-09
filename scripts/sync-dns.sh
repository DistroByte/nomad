#!/usr/bin/env bash
#
# Generate this estate's split-DNS records from the Traefik Host() rules defined
# in jobs/, which are the single source of truth for "what name does this
# service answer on".
#
# Two artefacts come out of the same list, because two different resolvers serve
# two different classes of client:
#
#   dnsmasq lines     for the Pi-holes on hermes and zeus, pointing each name at
#                     Traefik's LAN address. These answer the LAN, docker0 and
#                     any tailnet client that reaches a Pi-hole over the subnet
#                     route.
#   extra-records     for headscale, pointing each name at Traefik's *tailnet*
#                     address. These answer roaming clients directly out of the
#                     control plane, so a laptop away from home resolves and
#                     reaches private services without depending on a subnet
#                     route being up or approved.
#
# Explicit per-host records are emitted (rather than a `/dbyte.xyz/` wildcard) so
# that:
#   - MagicDNS names under ts.dbyte.xyz are never shadowed, and
#   - non-A lookups (TXT/MX, e.g. ACME DNS-01, SPF) for the zone still forward
#     upstream instead of being answered NODATA by dnsmasq.
#
# Usage:
#   scripts/sync-dns.sh                  # print both artefacts (dry run)
#   scripts/sync-dns.sh dnsmasq          # print the Pi-hole dnsmasq lines
#   scripts/sync-dns.sh extra-records    # print the headscale extra-records JSON
#   scripts/sync-dns.sh --apply          # push the dnsmasq lines to every Pi-hole
#
# Pushing the extra-records file to the control plane is ansible's job, not
# this script's — see ansible/playbooks/dns.yaml.
#
# Environment:
#   TRAEFIK_IP          Traefik's LAN address              (default 192.168.0.4)
#   TRAEFIK_TAILNET_IP  Traefik's tailnet address          (default 100.64.0.1)
#   PIHOLE_URLS         Space-separated Pi-hole API bases
#   PIHOLE_PASSWORD     Pi-hole admin password; read from Consul KV if unset
#   CONSUL_ADDR         Consul HTTP API, for that lookup   (default zeus:8500)
#   EXCLUDE_HOSTS       Space-separated names to leave out

set -euo pipefail

readonly TRAEFIK_IP="${TRAEFIK_IP:-192.168.0.4}"
readonly TRAEFIK_TAILNET_IP="${TRAEFIK_TAILNET_IP:-100.64.0.1}"
# dionysus is last and stays only for the soak: until it is retired it is still
# a resolver in DHCP, so a job's new Host() rule has to reach it too or the LAN
# gets inconsistent answers depending on which resolver a client picked. Drop it
# from this default when the old Pi-hole goes. A passwordless instance is fine
# alongside password-protected ones — see pihole_login.
readonly PIHOLE_URLS="${PIHOLE_URLS:-http://192.168.0.4:8053 http://192.168.0.3:8053 http://192.168.0.5}"
readonly CONSUL_ADDR="${CONSUL_ADDR:-http://192.168.0.3:8500}"

# headscale and headplane must resolve to worker's public address, never to
# Traefik: a node that cannot reach the control plane cannot rejoin the tailnet,
# and pointing those names inward is how that becomes unrecoverable.
readonly EXCLUDE_HOSTS="${EXCLUDE_HOSTS:-headscale.dbyte.xyz headplane.dbyte.xyz}"

readonly TAILNET_BASE_DOMAIN="ts.dbyte.xyz"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

is_excluded() {
  local host="$1" excluded
  for excluded in ${EXCLUDE_HOSTS}; do
    [[ "${host}" == "${excluded}" ]] && return 0
  done
  return 1
}

# Every Host() rule in a live job file, deduplicated and filtered.
service_hosts() {
  # shellcheck disable=SC2016  # the Host(...) patterns are literal regexes, not shell expansions
  grep -rEl 'Host\(`[^`]+`\)' "${repo_root}/jobs" --include='*.hcl' \
    | grep -v '/archive/' \
    | xargs grep -hoE 'Host\(`[^`]+`\)' \
    | sed -E 's/Host\(`([^`]+)`\)/\1/' \
    | sort -u \
    | while read -r host; do
        is_excluded "${host}" && continue
        printf '%s\n' "${host}"
      done
}

generate_dnsmasq_lines() {
  # Forwarders first. These are not derived from jobs/, but they belong in the
  # same array because Pi-hole's API replaces misc.dnsmasq_lines wholesale —
  # anything not emitted here is deleted on the next apply.
  #
  # The Consul forwarder is what keeps .consul resolving now that
  # systemd-resolved's stub listener is gone: the local agent answers on
  # 127.0.0.1:8600 and FTL runs with host networking, so the loopback is the
  # host's own.
  printf 'server=/consul/127.0.0.1#8600\n'
  # MagicDNS names for anything not pinned as a static record — tailscaled
  # answers on 100.100.100.100 regardless of whether the node accepts tailnet
  # DNS for itself.
  printf 'server=/%s/100.100.100.100\n' "${TAILNET_BASE_DOMAIN}"

  service_hosts | while read -r host; do
    printf 'address=/%s/%s\n' "${host}" "${TRAEFIK_IP}"
  done
}

generate_extra_records() {
  service_hosts \
    | jq -R --arg ip "${TRAEFIK_TAILNET_IP}" '{name: ., type: "A", value: $ip}' \
    | jq -s .
}

pihole_password() {
  if [[ -n "${PIHOLE_PASSWORD:-}" ]]; then
    printf '%s' "${PIHOLE_PASSWORD}"
    return 0
  fi
  # Same value the ansible vault holds; Consul is simply the copy a script can
  # read without unlocking a password manager.
  curl -fsS --connect-timeout 5 "${CONSUL_ADDR}/v1/kv/pihole/password?raw=true" 2>/dev/null || true
}

readonly PIHOLE_UNREACHABLE=2

# Echoes the session id, empty for a passwordless instance.
pihole_login() {
  local url="$1" password="$2" response valid status=0
  response="$(curl -fsS --connect-timeout 5 -X POST "${url}/api/auth" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg p "${password}" '{password: $p}')" 2>/dev/null)" || status=$?

  if ((status != 0)); then
    return "${PIHOLE_UNREACHABLE}"
  fi

  valid="$(printf '%s' "${response}" | jq -r '.session.valid // false')"
  if [[ "${valid}" != "true" ]]; then
    echo "error: ${url} rejected the password (check PIHOLE_PASSWORD or Consul KV pihole/password)" >&2
    return 1
  fi
  printf '%s' "$(printf '%s' "${response}" | jq -r '.session.sid // empty')"
}

apply_to_pihole() {
  local url="$1" lines_json="$2" password="$3" sid status=0
  sid="$(pihole_login "${url}" "${password}")" || status=$?

  if ((status == PIHOLE_UNREACHABLE)); then
    echo "warning: ${url} not reachable — skipping (are you on the tailnet?)" >&2
    return "${PIHOLE_UNREACHABLE}"
  elif ((status != 0)); then
    return 1
  fi

  local auth_header=()
  # A passwordless instance issues no sid and rejects an empty header.
  [[ -n "${sid}" ]] && auth_header=(-H "X-FTL-SID: ${sid}")

  # ${arr[@]+"${arr[@]}"} rather than "${arr[@]}": under `set -u`, bash 3.2 —
  # which is what /usr/bin/env bash still resolves to on macOS — treats an empty
  # array expansion as an unbound variable and aborts. That only bites for a
  # passwordless instance, i.e. dionysus, which would then silently stop
  # receiving record updates while still serving DHCP clients.
  curl -fsS -X PATCH "${url}/api/config" \
    -H 'Content-Type: application/json' \
    ${auth_header[@]+"${auth_header[@]}"} \
    -d "{\"config\":{\"misc\":{\"dnsmasq_lines\":${lines_json}}}}" >/dev/null

  if [[ -n "${sid}" ]]; then
    # Invalidate the session so it does not linger.
    curl -fsS -X DELETE "${url}/api/auth" -H "X-FTL-SID: ${sid}" >/dev/null || true
  fi
}

apply_lines() {
  local lines_json password url reachable=0 failed=0 status
  lines_json="$(generate_dnsmasq_lines | jq -R . | jq -s .)"
  password="$(pihole_password)"

  for url in ${PIHOLE_URLS}; do
    status=0
    apply_to_pihole "${url}" "${lines_json}" "${password}" || status=$?
    case "${status}" in
      0) reachable=$((reachable + 1)); echo "Applied $(generate_dnsmasq_lines | wc -l | tr -d ' ') lines to ${url}." >&2 ;;
      "${PIHOLE_UNREACHABLE}") ;;
      *) failed=$((failed + 1)) ;;
    esac
  done

  ((failed == 0)) || return 1

  # Reaching neither resolver is normal off-tailnet (this runs from a git hook),
  # but reaching only one means the pair has diverged and someone must know.
  if ((reachable > 0)) && ((reachable < $(wc -w <<<"${PIHOLE_URLS}"))); then
    echo "warning: only ${reachable} of $(wc -w <<<"${PIHOLE_URLS}") Pi-holes updated — the pair is now out of sync" >&2
    return 1
  fi
}

main() {
  case "${1:-}" in
    --apply)       apply_lines ;;
    dnsmasq)       generate_dnsmasq_lines ;;
    extra-records) generate_extra_records ;;
    "")
      echo "# dnsmasq lines (Pi-hole misc.dnsmasq_lines)"
      generate_dnsmasq_lines
      echo
      echo "# headscale extra-records.json"
      generate_extra_records
      ;;
    *) echo "usage: $0 [--apply | dnsmasq | extra-records]" >&2; exit 2 ;;
  esac
}

main "$@"
