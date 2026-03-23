#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <domain> <public-ip> [timeout-seconds]" >&2
  exit 1
fi

domain="$1"
public_ip="$2"
timeout_seconds="${3:-1200}"
interval=10
elapsed=0

while (( elapsed < timeout_seconds )); do
  if json="$(curl -ksS --connect-timeout 5 --max-time 10 --resolve "${domain}:443:${public_ip}" "https://${domain}/__bootstrap" 2>/dev/null)"; then
    if jq -e '.bootstrap_complete == true' >/dev/null 2>&1 <<<"$json"; then
      echo "$json"
      exit 0
    fi
  fi

  sleep "$interval"
  ((elapsed+=interval))
  echo "Waiting for cloud-init/bootstrap completion on ${domain} (${elapsed}s/${timeout_seconds}s)..." >&2

done

echo "Timed out waiting for cloud-init to complete on ${domain}" >&2
exit 1
