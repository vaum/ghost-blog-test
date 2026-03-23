#!/usr/bin/env bash

set -euo pipefail

status_dir="/opt/ghost/status"
status_file="${status_dir}/bootstrap-status.json"
mkdir -p "$status_dir"

bootstrap_complete=false
[[ -f /var/lib/bootstrap-complete ]] && bootstrap_complete=true

tailscale_online=false
tailscale_ip=""
tailscale_name=""

if tailscale status --json >/tmp/tailscale-status.json 2>/dev/null; then
  if jq -e '.BackendState == "Running"' /tmp/tailscale-status.json >/dev/null 2>&1; then
    tailscale_online=true
  fi
  tailscale_name="$(jq -r '.Self.DNSName // empty' /tmp/tailscale-status.json)"
fi

tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"

docker_stack_healthy=false
compose_cmd=(docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env)

service_healthy_or_running() {
  local service="$1"
  local cid state

  cid="$("${compose_cmd[@]}" ps -q "$service" 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 1

  state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
  [[ "$state" == "healthy" || "$state" == "running" ]]
}

if service_healthy_or_running "db" && service_healthy_or_running "ghost" && service_healthy_or_running "caddy"; then
  docker_stack_healthy=true
fi

jq -n \
  --arg server_name "{{SERVER_NAME}}" \
  --arg domain "{{DOMAIN}}" \
  --arg admin_domain "{{ADMIN_DOMAIN}}" \
  --arg tailscale_ip "$tailscale_ip" \
  --arg tailscale_name "$tailscale_name" \
  --arg timestamp "$(date --iso-8601=seconds)" \
  --argjson bootstrap_complete "$bootstrap_complete" \
  --argjson tailscale_online "$tailscale_online" \
  --argjson docker_stack_healthy "$docker_stack_healthy" \
  '{
    bootstrap_complete: $bootstrap_complete,
    docker_stack_healthy: $docker_stack_healthy,
    tailscale_online: $tailscale_online,
    server_name: $server_name,
    domain: $domain,
    admin_domain: $admin_domain,
    tailscale_name: $tailscale_name,
    tailscale_ip: $tailscale_ip,
    checked_at: $timestamp
  }' > "$status_file"
