#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/common.sh"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
GENERATED_DIR="$ROOT_DIR/.generated"
mkdir -p "$GENERATED_DIR"

load_env "$ENV_FILE"

HCLOUD_IMAGE="${HCLOUD_IMAGE:-ubuntu-24.04}"
GHOST_VERSION="${GHOST_VERSION:-6-alpine}"
TIMEZONE="${TIMEZONE:-UTC}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-}"
EMAIL_FOR_TLS="${EMAIL_FOR_TLS:-}"
ENABLE_BACKUPS="${ENABLE_BACKUPS:-false}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * *}"
LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"

require_commands bash curl jq hcloud perl
if ! command_exists timeout && ! command_exists nc; then
  die "Either timeout or nc is required for TCP/22 checks"
fi
if ! command_exists timeout; then
  warn "'timeout' not found; falling back to 'nc' for port checks"
fi

require_env_vars \
  HCLOUD_TOKEN \
  HCLOUD_LOCATION \
  HCLOUD_SERVER_TYPE \
  SERVER_NAME \
  DOMAIN \
  TAILSCALE_AUTH_KEY \
  TAILSCALE_TAILNET \
  SSH_ADMIN_USER \
  MYSQL_ROOT_PASSWORD \
  MYSQL_PASSWORD

ensure_hcloud_auth

if [[ "$SERVER_NAME" =~ [^a-zA-Z0-9.-] ]]; then
  die "SERVER_NAME contains unsupported characters"
fi

if [[ "$DOMAIN" == http://* || "$DOMAIN" == https://* || "$DOMAIN" == */* ]]; then
  die "DOMAIN must be a hostname only (no scheme/path)"
fi

if [[ -n "$ADMIN_DOMAIN" ]]; then
  if [[ "$ADMIN_DOMAIN" == http://* || "$ADMIN_DOMAIN" == https://* || "$ADMIN_DOMAIN" == */* ]]; then
    die "ADMIN_DOMAIN must be a hostname only (no scheme/path)"
  fi
fi

FIREWALL_NAME="${SERVER_NAME}-ghost-fw"
BOOTSTRAP_JSON_FILE="$GENERATED_DIR/bootstrap-status.json"

render_template() {
  "$ROOT_DIR/scripts/render-template.sh" "$1" "$2"
}

b64_file() {
  base64 < "$1" | tr -d '\n'
}

build_caddy_blocks() {
  local caddy_global_options=""

  if [[ -n "$EMAIL_FOR_TLS" ]]; then
    caddy_global_options+="  email ${EMAIL_FOR_TLS}"
  fi

  if is_true "$LETSENCRYPT_STAGING"; then
    if [[ -n "$caddy_global_options" ]]; then
      caddy_global_options+=$'\n'
    fi
    caddy_global_options+="  acme_ca https://acme-staging-v02.api.letsencrypt.org/directory"
  fi

  if [[ -z "$caddy_global_options" ]]; then
    caddy_global_options="  # default Caddy ACME settings"
  fi

  CADDY_GLOBAL_OPTIONS="$caddy_global_options"
  export CADDY_GLOBAL_OPTIONS

  ADMIN_DOMAIN_BLOCK=""
  if [[ -n "$ADMIN_DOMAIN" ]]; then
    ADMIN_DOMAIN_BLOCK="$(cat <<BLOCK
${ADMIN_DOMAIN} {
  encode gzip zstd

  @bootstrap path /__bootstrap
  handle @bootstrap {
    root * /srv/status
    rewrite * /bootstrap-status.json
    file_server
  }

  reverse_proxy ghost:2368
}
BLOCK
)"
  fi
  export ADMIN_DOMAIN_BLOCK
}

build_optional_ghost_admin_url() {
  if [[ -n "$ADMIN_DOMAIN" ]]; then
    GHOST_ADMIN_URL_LINE="admin__url=https://${ADMIN_DOMAIN}"
  else
    GHOST_ADMIN_URL_LINE="# admin__url can be set by ADMIN_DOMAIN"
  fi
  export GHOST_ADMIN_URL_LINE
}

build_backup_cron_content() {
  local cron_line
  if is_true "$ENABLE_BACKUPS"; then
    cron_line="${BACKUP_SCHEDULE} root /usr/local/bin/ghost-backup.sh >> /var/log/ghost-backup.log 2>&1"
  else
    cron_line="# Backups disabled (ENABLE_BACKUPS=false)"
  fi

  BACKUP_CRON_B64="$(printf '%s\n' "$cron_line" | base64 | tr -d '\n')"
  export BACKUP_CRON_B64
}

render_all_templates() {
  export DOMAIN ADMIN_DOMAIN GHOST_VERSION MYSQL_ROOT_PASSWORD MYSQL_PASSWORD TIMEZONE SERVER_NAME

  build_optional_ghost_admin_url
  build_caddy_blocks
  build_backup_cron_content

  render_template "$ROOT_DIR/templates/compose.yaml.tpl" "$GENERATED_DIR/compose.yaml"
  render_template "$ROOT_DIR/templates/ghost.env.tpl" "$GENERATED_DIR/ghost.env"
  render_template "$ROOT_DIR/templates/Caddyfile.tpl" "$GENERATED_DIR/Caddyfile"
  render_template "$ROOT_DIR/templates/bootstrap-status.sh.tpl" "$GENERATED_DIR/ghost-write-bootstrap-status.sh"
  render_template "$ROOT_DIR/templates/backup.sh.tpl" "$GENERATED_DIR/ghost-backup.sh"

  export COMPOSE_B64="$(b64_file "$GENERATED_DIR/compose.yaml")"
  export CADDYFILE_B64="$(b64_file "$GENERATED_DIR/Caddyfile")"
  export GHOST_ENV_B64="$(b64_file "$GENERATED_DIR/ghost.env")"
  export STATUS_SCRIPT_B64="$(b64_file "$GENERATED_DIR/ghost-write-bootstrap-status.sh")"
  export BACKUP_SCRIPT_B64="$(b64_file "$GENERATED_DIR/ghost-backup.sh")"

  export SSH_ADMIN_USER TAILSCALE_AUTH_KEY SERVER_NAME TIMEZONE

  render_template "$ROOT_DIR/cloud-init/user-data.yaml.tpl" "$GENERATED_DIR/user-data.yaml"
}

create_or_get_firewall() {
  local firewall_json
  firewall_json="$(hcloud_firewall_json "$FIREWALL_NAME" || true)"

  if [[ -n "$firewall_json" ]]; then
    local managed_by
    managed_by="$(jq -r --arg key "$PROJECT_LABEL_KEY" '.labels[$key] // empty' <<<"$firewall_json")"
    if [[ -n "$managed_by" && "$managed_by" != "$PROJECT_LABEL_VALUE" ]]; then
      die "Firewall ${FIREWALL_NAME} exists but is not managed by this project"
    fi

    FIREWALL_ID="$(jq -r '.id' <<<"$firewall_json")"
    info "Reusing existing firewall: ${FIREWALL_NAME} (id=${FIREWALL_ID})"
    return
  fi

  print_header "Creating Firewall"
  local create_json
  create_json="$(hcloud firewall create \
    --name "$FIREWALL_NAME" \
    --label "${PROJECT_LABEL_KEY}=${PROJECT_LABEL_VALUE}" \
    --label "${STACK_LABEL_KEY}=${STACK_LABEL_VALUE}" \
    --label "server-name=${SERVER_NAME}" \
    --rule "direction=in,protocol=tcp,port=80,source_ips=0.0.0.0/0,::/0" \
    --rule "direction=in,protocol=tcp,port=443,source_ips=0.0.0.0/0,::/0" \
    --rule "direction=in,protocol=icmp,source_ips=0.0.0.0/0,::/0" \
    -o json)"

  FIREWALL_ID="$(jq -r '.firewall.id // .id' <<<"$create_json")"
  [[ -n "$FIREWALL_ID" && "$FIREWALL_ID" != "null" ]] || die "Failed to create firewall"

  info "Created firewall: ${FIREWALL_NAME} (id=${FIREWALL_ID})"
}

create_or_get_server() {
  local server_json
  server_json="$(hcloud_server_json "$SERVER_NAME" || true)"

  if [[ -n "$server_json" ]]; then
    SERVER_ID="$(jq -r '.id' <<<"$server_json")"
    SERVER_IP="$(jq -r '.public_net.ipv4.ip // empty' <<<"$server_json")"
    info "Reusing existing server: ${SERVER_NAME} (id=${SERVER_ID}, ip=${SERVER_IP})"
    return
  fi

  print_header "Creating Server"
  local create_json
  create_json="$(hcloud server create \
    --name "$SERVER_NAME" \
    --type "$HCLOUD_SERVER_TYPE" \
    --image "$HCLOUD_IMAGE" \
    --location "$HCLOUD_LOCATION" \
    --user-data-from-file "$GENERATED_DIR/user-data.yaml" \
    --label "${PROJECT_LABEL_KEY}=${PROJECT_LABEL_VALUE}" \
    --label "${STACK_LABEL_KEY}=${STACK_LABEL_VALUE}" \
    --label "server-name=${SERVER_NAME}" \
    -o json)"

  SERVER_ID="$(jq -r '.server.id // .id' <<<"$create_json")"
  SERVER_IP="$(jq -r '.server.public_net.ipv4.ip // .public_net.ipv4.ip // empty' <<<"$create_json")"
  [[ -n "$SERVER_ID" && "$SERVER_ID" != "null" ]] || die "Failed to create server"

  info "Created server: ${SERVER_NAME} (id=${SERVER_ID}, ip=${SERVER_IP})"
}

attach_firewall_to_server() {
  print_header "Ensuring Firewall Attachment"

  if hcloud firewall apply-to-resource "$FIREWALL_NAME" --server "$SERVER_NAME" >/dev/null 2>&1; then
    info "Firewall attached via apply-to-resource"
    return
  fi

  if hcloud firewall apply-to-resource "$FIREWALL_ID" --server "$SERVER_ID" >/dev/null 2>&1; then
    info "Firewall attached via fallback apply-to-resource"
    return
  fi

  if hcloud firewall apply-to-resource "$FIREWALL_NAME" --type server --server "$SERVER_NAME" >/dev/null 2>&1; then
    info "Firewall attached via compatibility apply-to-resource"
    return
  fi

  die "Failed to attach firewall to server"
}

wait_for_server_ip() {
  local elapsed=0
  local max_wait=600
  local interval=5

  while (( elapsed < max_wait )); do
    local server_desc
    server_desc="$(hcloud server describe "$SERVER_NAME" -o json)"
    SERVER_IP="$(jq -r '.public_net.ipv4.ip // empty' <<<"$server_desc")"

    if [[ -n "$SERVER_IP" ]]; then
      return
    fi

    sleep "$interval"
    ((elapsed+=interval))
  done

  die "Timed out waiting for server public IPv4"
}

wait_for_cloud_init_marker() {
  print_header "Waiting for Cloud-Init"

  "$ROOT_DIR/scripts/wait-for-cloud-init.sh" "$DOMAIN" "$SERVER_IP" 1800 > "$BOOTSTRAP_JSON_FILE"
  info "Cloud-init bootstrap marker confirmed"
}

validate_firewall_attachment() {
  local server_desc
  server_desc="$(hcloud server describe "$SERVER_NAME" -o json)"

  if jq -e --arg fw_name "$FIREWALL_NAME" '.public_net.firewalls[]? | select(.name == $fw_name)' >/dev/null <<<"$server_desc"; then
    return
  fi

  if jq -e --argjson fw_id "$FIREWALL_ID" '.public_net.firewalls[]? | select(.id == $fw_id)' >/dev/null <<<"$server_desc"; then
    return
  fi

  die "Firewall is not attached to server according to Hetzner metadata"
}

run_post_checks() {
  print_header "Running Acceptance Checks"
  "$ROOT_DIR/scripts/health-check.sh" "$DOMAIN" "$ADMIN_DOMAIN" "$SERVER_IP" "$BOOTSTRAP_JSON_FILE"
  validate_firewall_attachment

  if ! jq -e '(.tailscale_name | length > 0) and (.tailscale_ip | length > 0)' "$BOOTSTRAP_JSON_FILE" >/dev/null; then
    die "Tailscale details were not populated in bootstrap status"
  fi

  if [[ -n "$TAILSCALE_TAILNET" ]]; then
    if ! jq -e --arg tailnet "$TAILSCALE_TAILNET" '.tailscale_name | contains($tailnet)' "$BOOTSTRAP_JSON_FILE" >/dev/null; then
      warn "Tailscale name does not include expected tailnet '${TAILSCALE_TAILNET}'"
    fi
  fi
}

print_summary() {
  local blog_url admin_url tailscale_name tailscale_ip

  blog_url="https://${DOMAIN}"
  if [[ -n "$ADMIN_DOMAIN" ]]; then
    admin_url="https://${ADMIN_DOMAIN}/ghost/"
  else
    admin_url="https://${DOMAIN}/ghost/"
  fi

  tailscale_name="$(jq -r '.tailscale_name // "unknown"' "$BOOTSTRAP_JSON_FILE")"
  tailscale_ip="$(jq -r '.tailscale_ip // "unknown"' "$BOOTSTRAP_JSON_FILE")"

  print_header "Deployment Complete"
  cat <<SUMMARY
Blog URL:           ${blog_url}
Admin URL:          ${admin_url}
Server Name:        ${SERVER_NAME}
Server Public IP:   ${SERVER_IP}
Tailnet:            ${TAILSCALE_TAILNET}
Tailscale Name:     ${tailscale_name}
Tailscale IP:       ${tailscale_ip}

Next commands:
  tailscale status
  tailscale ssh ${SSH_ADMIN_USER}@${SERVER_NAME}
  ssh ${SSH_ADMIN_USER}@${tailscale_ip}
  hcloud server describe ${SERVER_NAME}
SUMMARY
}

print_header "Rendering Templates"
render_all_templates

create_or_get_firewall
create_or_get_server
attach_firewall_to_server
wait_for_server_ip
wait_for_cloud_init_marker
run_post_checks
print_summary
