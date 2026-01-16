#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Link Plugin (Jar-only Dynamic Plugin Manager)
# ------------------------------------------------------------------------------
# - Links only *.jar files into servers/<name>/plugins
# - Does NOT touch directories or non-jar files under plugins/
# - Builds desired jar set in temp dir, then swaps jars safely.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
PLUGIN_LIB_ROOT="${ROOT_PATH}/libraries/plugins"
INSTANCES_ROOT="${ROOT_PATH}/servers"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

# Logging helper functions
log_info() { echo -e "[$(date '+%H:%M:%S') ${GREEN}INFO${NC}] [link-library]: $1"; }
log_warn() { echo -e "[$(date '+%H:%M:%S') ${YELLOW}WARN${NC}] [link-library]: $1"; }
log_err() { echo -e "[$(date '+%H:%M:%S') ${RED}ERROR${NC}] [link-library]: $1" >&2; }

# Pick latest file matching pattern in dir
pick_latest() { # <dir> <glob>
  local dir="$1" pattern="$2"
  [[ -d "$dir" ]] || {
    echo ""
    return 0
  }

  # Sort by basename version-ish; return full path
  find "$dir" -maxdepth 1 -type f -iname "$pattern" 2>/dev/null |
    awk -F/ '{print $NF "\t" $0}' |
    sort -V |
    tail -n1 |
    cut -f2-
}

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

# Make sure we have the tools we need.
for cmd in jq realpath find awk sort mktemp mv ln rm; do
  if ! command -v "$cmd" >/dev/null; then
    log_err "Missing dependency: '$cmd'. Please install it first."

    exit 1
  fi
done

# Check config file
[[ -f "$CONFIG_FILE" ]] || {
  log_err "Config file missing: $CONFIG_FILE"
  exit 1
}

# Ensure plugin lib root exists
mkdir -p "$PLUGIN_LIB_ROOT"

# Ensure instance root exists
mkdir -p "$INSTANCES_ROOT"

# ------------------------------------------------------------------------------
# Plugin Linking Logic
# ------------------------------------------------------------------------------

# Link plugins for a server instance
link_server_plugins() {
  local server_name="$1"
  local engine="$2"
  local instance_dir="$3"
  local tag="${server_name}"

  local dest_dir="${instance_dir}/plugins"
  local engine_lib_root="${PLUGIN_LIB_ROOT}/${engine}"
  local managed_lib_dir="${engine_lib_root}/Managed"

  mkdir -p "$dest_dir"

  # plugins config may be missing
  if ! jq -e ".servers[\"${server_name}\"].plugins? | type==\"object\"" "$CONFIG_FILE" >/dev/null 2>&1; then
    log_warn "No plugins configured for ${server_name}. Skipping."

    return 0
  fi

  # Build in temp dir under instance (same filesystem)
  local temp_build_dir
  temp_build_dir="$(mktemp -d -p "$instance_dir" ".plugins_build_XXXXXX")"

  # Ensure cleanup on error
  trap 'rm -rf "$temp_build_dir" 2>/dev/null || true' RETURN

  mapfile -t ENTRIES < <(
    jq -r ".servers[\"${server_name}\"].plugins
           | to_entries[]
           | \"\(.key)\t\(.value.type)\t\(.value.pattern)\"" \
      "$CONFIG_FILE"
  )

  local linked=0
  local missing=0

  for entry in "${ENTRIES[@]}"; do
    local plugin_key type pattern src_file=""

    plugin_key="${entry%%$'\t'*}"
    type="${entry#*$'\t'}"
    type="${type%%$'\t'*}"
    pattern="${entry##*$'\t'}"

    case "$type" in
    auto) src_file="$(pick_latest "$managed_lib_dir" "$pattern")" ;;
    manual) src_file="$(pick_latest "$engine_lib_root" "$pattern")" ;;
    *)
      log_warn "Unknown type '$type' for '${plugin_key}' in ${server_name} (skipping)"
      continue
      ;;
    esac

    if [[ -n "${src_file:-}" && -f "$src_file" ]]; then
      ln -sfn "$src_file" "${temp_build_dir}/${plugin_key}.jar"
      log_info "Linked ${plugin_key}.jar for ${server_name} -> $(basename "$src_file")"
      ((linked++)) || true
    else
      log_warn "${plugin_key}.jar (pattern: ${pattern}) not found for engine=${engine} in ${server_name}"
      ((missing++)) || true
    fi
  done

  # If nothing linked, preserve existing jars
  if [[ $linked -eq 0 ]]; then
    log_warn "No plugins linked for ${server_name}. Preserving existing *.jar in ${dest_dir}"
    return 0
  fi

  # -------------------------
  # Safe apply (jar-only)
  # -------------------------
  # Strategy:
  # 1) Move current managed jars (matching our plugin_key set) to backup dir
  # 2) Move new jars into dest_dir
  # 3) If move succeeds, delete backups for managed jars
  #
  # We ONLY touch jars we manage (plugin_key.jar), leaving other jars/directories intact.
  local backup_dir="${instance_dir}/.plugins_backup_$$"

  # Create backup dir
  mkdir -p "$backup_dir"

  # Backup managed targets (by name)
  for entry in "${ENTRIES[@]}"; do
    local plugin_key="${entry%%$'\t'*}"
    local target="${dest_dir}/${plugin_key}.jar"

    if [[ -e "$target" || -L "$target" ]]; then
      mv -f "$target" "$backup_dir/" 2>/dev/null || true
    fi
  done

  # Move new jars into place
  local failed_apply=0

  shopt -s nullglob

  for f in "${temp_build_dir}"/*.jar; do
    if ! mv -f "$f" "$dest_dir/"; then
      failed_apply=1
      break
    fi
  done

  shopt -u nullglob

  if [[ $failed_apply -ne 0 ]]; then
    # Rollback: restore backups
    log_warn "Apply failed for ${server_name}. Rolling back..."
    shopt -s nullglob

    for b in "$backup_dir"/*.jar; do
      mv -f "$b" "$dest_dir/" 2>/dev/null || true
    done
    shopt -u nullglob

    rm -rf "$backup_dir" 2>/dev/null || true
    log_err "Failed to apply plugins for ${server_name}."

    return 1
  fi

  # Cleanup backups (managed jars only)
  rm -rf "$backup_dir" 2>/dev/null || true

  if [[ $missing -gt 0 ]]; then
    log_warn "Linked for ${server_name}, but with ${missing} missing plugin(s)."
  else
    log_info "All plugins linked for ${server_name}."
  fi
}

# ------------------------------------------------------------------------------
# Main Process Logic
# ------------------------------------------------------------------------------

# Load configuration file
CONFIG="$(cat "$CONFIG_FILE")"

jq -e '.servers and (.servers | type=="object")' >/dev/null <<<"$CONFIG" ||
  {
    log_err "Invalid config: expected '.servers' object in ${CONFIG_FILE}"
    exit 1
  }

# Get servers safely (no subshell loop)
mapfile -t SERVERS < <(jq -r '.servers | keys[]' <<<"$CONFIG")

for SERVER in "${SERVERS[@]}"; do
  ENGINE="$(jq -r ".servers[\"$SERVER\"].engine // empty" <<<"$CONFIG")"
  SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"

  # Validate engine and server dir
  if [[ -z "$ENGINE" ]]; then
    log_warn "Missing engine for ${SERVER} in config. Skipping plugins."

    continue
  fi

  if [[ ! -d "$SERVER_DIR" ]]; then
    log_warn "Instance directory missing for ${SERVER} in config. Skipping plugins."

    continue
  fi

  log_info "Linking Plugins: ${BLUE}${SERVER}${NC} (${ENGINE})"

  link_server_plugins "$SERVER" "$ENGINE" "$SERVER_DIR"
done

log_info "Plugin linking complete."
exit 0
