#!/usr/bin/env bash

set -o pipefail

readonly PROJECT_LABEL_KEY="managed-by"
readonly PROJECT_LABEL_VALUE="ghost-oneclick"
readonly STACK_LABEL_KEY="stack"
readonly STACK_LABEL_VALUE="ghost"

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

info() {
  log "INFO" "$@"
}

warn() {
  log "WARN" "$@" >&2
}

error() {
  log "ERROR" "$@" >&2
}

die() {
  error "$@"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_commands() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}"
  fi
}

load_env() {
  local env_file="$1"
  [[ -f "$env_file" ]] || die "Missing env file: $env_file"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

require_env_vars() {
  local missing=()
  local var

  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required environment variables: ${missing[*]}"
  fi
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

project_label_selector() {
  printf '%s=%s,%s=%s' \
    "$PROJECT_LABEL_KEY" "$PROJECT_LABEL_VALUE" \
    "$STACK_LABEL_KEY" "$STACK_LABEL_VALUE"
}

ensure_hcloud_auth() {
  hcloud server list -o json >/dev/null 2>&1 || die "Unable to authenticate to Hetzner Cloud via hcloud. Check HCLOUD_TOKEN."
}

hcloud_server_json() {
  hcloud server list -o json | jq -c --arg name "$1" '.[] | select(.name == $name)'
}

hcloud_firewall_json() {
  hcloud firewall list -o json | jq -c --arg name "$1" '.[] | select(.name == $name)'
}

print_header() {
  printf '\n==== %s ====\n' "$1"
}
