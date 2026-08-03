#!/usr/bin/env bash
#
# Generate Pi-hole local-DNS overrides from the Traefik Host() rules defined in
# this repo, so every app served by Traefik resolves to the LAN address of
# hermes on both the local network and the tailnet.
#
# Explicit per-host records are emitted (rather than a `/dbyte.xyz/` wildcard)
# so that:
#   - MagicDNS names under ts.dbyte.xyz are never shadowed, and
#   - non-A lookups (TXT/MX, e.g. ACME DNS-01, SPF) for the zone still forward
#     upstream instead of being answered NODATA by dnsmasq.
#
# Usage:
#   scripts/sync-pihole-dns.sh            # print the generated dnsmasq lines
#   scripts/sync-pihole-dns.sh --apply    # push them to Pi-hole's dnsmasq_lines
#
# Environment:
#   TRAEFIK_IP        LAN address of the Traefik node          (default 192.168.0.4)
#   PIHOLE_URL        Pi-hole v6 API base URL                  (default http://dionysus.internal)
#   PIHOLE_PASSWORD   Pi-hole admin password, "" if unset      (default "")

set -euo pipefail

readonly TRAEFIK_IP="${TRAEFIK_IP:-192.168.0.4}"
readonly PIHOLE_URL="${PIHOLE_URL:-http://dionysus.internal}"
readonly PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-}"

# Hosts to keep on public DNS instead of pointing at Traefik locally. The
# headscale control plane and its UI are excluded so they always resolve to the
# public IP — a cold tailscaled start from away needs to reach headscale before
# the tunnel (and thus the LAN route) exists. Local records target the
# media-heavy apps that would otherwise hairpin through the exit node.
# Space-separated; override via the EXCLUDE_HOSTS environment variable.
readonly EXCLUDE_HOSTS="${EXCLUDE_HOSTS:-headscale.dbyte.xyz headplane.dbyte.xyz}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

is_excluded() {
  local host="$1" excluded
  for excluded in ${EXCLUDE_HOSTS}; do
    [[ "${host}" == "${excluded}" ]] && return 0
  done
  return 1
}

generate_lines() {
  # Collect every Host(`fqdn`) from active jobs (excluding jobs/archive), dedupe,
  # and emit one explicit dnsmasq address= record per host pointing at Traefik.
  # shellcheck disable=SC2016  # the Host(...) patterns are literal regexes, not shell expansions
  grep -rEl 'Host\(`[^`]+`\)' "${repo_root}/jobs" --include='*.hcl' \
    | grep -v '/archive/' \
    | xargs grep -hoE 'Host\(`[^`]+`\)' \
    | sed -E 's/Host\(`([^`]+)`\)/\1/' \
    | sort -u \
    | while read -r host; do
        is_excluded "${host}" && continue
        printf 'address=/%s/%s\n' "${host}" "${TRAEFIK_IP}"
      done
}

pihole_session() {
  # Echo a session id for authenticated requests. A passwordless Pi-hole reports
  # a valid session with a null sid ("no password set") — in that case the API is
  # open and no sid is needed, so echo nothing and succeed.
  local response valid sid
  response="$(curl -fsS -X POST "${PIHOLE_URL}/api/auth" \
    -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PIHOLE_PASSWORD}\"}")"
  valid="$(printf '%s' "${response}" | jq -r '.session.valid // false')"
  sid="$(printf '%s' "${response}" | jq -r '.session.sid // empty')"
  if [[ "${valid}" != "true" ]]; then
    echo "error: Pi-hole authentication failed (check PIHOLE_PASSWORD)" >&2
    return 1
  fi
  printf '%s' "${sid}"
}

apply_lines() {
  local lines_json sid
  lines_json="$(generate_lines | jq -R . | jq -s .)"
  sid="$(pihole_session)"

  # Only send the session header when a sid was issued (password-protected
  # instances); a passwordless instance rejects an empty header.
  local auth_header=()
  [[ -n "${sid}" ]] && auth_header=(-H "X-FTL-SID: ${sid}")

  curl -fsS -X PATCH "${PIHOLE_URL}/api/config" \
    -H 'Content-Type: application/json' \
    "${auth_header[@]}" \
    -d "{\"config\":{\"misc\":{\"dnsmasq_lines\":${lines_json}}}}" >/dev/null

  if [[ -n "${sid}" ]]; then
    # Invalidate the session so it does not linger.
    curl -fsS -X DELETE "${PIHOLE_URL}/api/auth" -H "X-FTL-SID: ${sid}" >/dev/null || true
  fi

  echo "Applied $(generate_lines | wc -l | tr -d ' ') records to Pi-hole." >&2
}

main() {
  case "${1:-}" in
    --apply) apply_lines ;;
    "")      generate_lines ;;
    *)       echo "usage: $0 [--apply]" >&2; exit 2 ;;
  esac
}

main "$@"
