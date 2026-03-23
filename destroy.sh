#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/common.sh"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      YES=true
      shift
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

load_env "$ENV_FILE"

require_commands bash jq hcloud
require_env_vars HCLOUD_TOKEN SERVER_NAME

ensure_hcloud_auth

FIREWALL_NAME="${SERVER_NAME}-ghost-fw"

server_json="$(hcloud_server_json "$SERVER_NAME" || true)"
firewall_json="$(hcloud_firewall_json "$FIREWALL_NAME" || true)"

if [[ -z "$server_json" && -z "$firewall_json" ]]; then
  info "No managed resources found for SERVER_NAME=${SERVER_NAME}. Nothing to delete."
  exit 0
fi

if [[ -n "$server_json" ]]; then
  server_managed_by="$(jq -r --arg key "$PROJECT_LABEL_KEY" '.labels[$key] // empty' <<<"$server_json")"
  if [[ "$server_managed_by" != "$PROJECT_LABEL_VALUE" ]]; then
    die "Server ${SERVER_NAME} exists but is not labeled as managed-by=${PROJECT_LABEL_VALUE}. Refusing to delete."
  fi
fi

if [[ -n "$firewall_json" ]]; then
  firewall_managed_by="$(jq -r --arg key "$PROJECT_LABEL_KEY" '.labels[$key] // empty' <<<"$firewall_json")"
  if [[ "$firewall_managed_by" != "$PROJECT_LABEL_VALUE" ]]; then
    die "Firewall ${FIREWALL_NAME} exists but is not labeled as managed-by=${PROJECT_LABEL_VALUE}. Refusing to delete."
  fi
fi

if ! $YES; then
  echo "This will delete managed resources for SERVER_NAME=${SERVER_NAME}:"
  [[ -n "$server_json" ]] && echo "  - server: ${SERVER_NAME}"
  [[ -n "$firewall_json" ]] && echo "  - firewall: ${FIREWALL_NAME}"
  read -r -p "Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || die "Aborted by user"
fi

if [[ -n "$server_json" ]]; then
  print_header "Deleting Server"
  hcloud server delete "$SERVER_NAME"
  info "Delete requested for server ${SERVER_NAME}"

  # Wait briefly for detach/delete propagation before firewall deletion.
  for _ in {1..30}; do
    if [[ -z "$(hcloud_server_json "$SERVER_NAME" || true)" ]]; then
      break
    fi
    sleep 2
  done
fi

if [[ -n "$firewall_json" ]]; then
  print_header "Deleting Firewall"
  hcloud firewall delete "$FIREWALL_NAME"
  info "Delete requested for firewall ${FIREWALL_NAME}"
fi

print_header "Destroy Complete"
info "All requested managed resources were deleted"
