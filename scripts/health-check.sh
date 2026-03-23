#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <domain> <admin-domain-or-empty> <public-ip> <bootstrap-json-file>" >&2
  exit 1
fi

domain="$1"
admin_domain="$2"
public_ip="$3"
bootstrap_json_file="$4"

if [[ ! -f "$bootstrap_json_file" ]]; then
  echo "Missing bootstrap JSON file: $bootstrap_json_file" >&2
  exit 1
fi

if ! jq -e '.bootstrap_complete == true' "$bootstrap_json_file" >/dev/null; then
  echo "Bootstrap marker not complete in bootstrap JSON" >&2
  exit 1
fi

if ! jq -e '.docker_stack_healthy == true' "$bootstrap_json_file" >/dev/null; then
  echo "Docker stack is not healthy according to bootstrap status" >&2
  exit 1
fi

if ! jq -e '.tailscale_online == true' "$bootstrap_json_file" >/dev/null; then
  echo "Tailscale is not online according to bootstrap status" >&2
  exit 1
fi

http_headers="$(curl -ksSI --connect-timeout 5 --max-time 10 --resolve "${domain}:80:${public_ip}" "http://${domain}/")"
http_code="$(awk 'toupper($1) ~ /^HTTP\// { code=$2 } END { print code }' <<<"$http_headers")"
location_header="$(awk 'tolower($1) == "location:" {print $2}' <<<"$http_headers" | tr -d '\r')"

case "$http_code" in
  301|302|307|308) ;;
  *)
    echo "Expected HTTP redirect to HTTPS for ${domain}, got status ${http_code}" >&2
    exit 1
    ;;
esac

if [[ "$location_header" != https://* ]]; then
  echo "Expected Location header to point to HTTPS, got: ${location_header:-<empty>}" >&2
  exit 1
fi

curl -ksSf --connect-timeout 10 --max-time 20 --resolve "${domain}:443:${public_ip}" "https://${domain}/" >/dev/null

if [[ -n "$admin_domain" ]]; then
  curl -ksSf --connect-timeout 10 --max-time 20 --resolve "${admin_domain}:443:${public_ip}" "https://${admin_domain}/ghost/" >/dev/null
else
  curl -ksSf --connect-timeout 10 --max-time 20 --resolve "${domain}:443:${public_ip}" "https://${domain}/ghost/" >/dev/null
fi

if command -v timeout >/dev/null 2>&1; then
  if timeout 3 bash -c "</dev/tcp/${public_ip}/22" >/dev/null 2>&1; then
    echo "Public TCP/22 appears open on ${public_ip}" >&2
    exit 1
  fi
else
  if nc -z -w 3 "$public_ip" 22 >/dev/null 2>&1; then
    echo "Public TCP/22 appears open on ${public_ip}" >&2
    exit 1
  fi
fi

wait_public_url() {
  local url="$1"
  local timeout_seconds="${2:-1200}"
  local elapsed=0
  local interval=15

  while (( elapsed < timeout_seconds )); do
    if curl -fsS --connect-timeout 10 --max-time 20 "$url" >/dev/null 2>&1; then
      return 0
    fi

    sleep "$interval"
    ((elapsed+=interval))
    echo "Waiting for public HTTPS readiness: ${url} (${elapsed}s/${timeout_seconds}s)" >&2
  done

  echo "Timed out waiting for public URL: ${url}" >&2
  return 1
}

wait_public_url "https://${domain}/"

if [[ -n "$admin_domain" ]]; then
  wait_public_url "https://${admin_domain}/ghost/"
fi
