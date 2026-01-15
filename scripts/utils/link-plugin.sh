#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Link Plugin (Jar-only Dynamic Plugin Manager)
# ------------------------------------------------------------------------------
# - Links only *.jar files into servers/<name>/plugins
# - Does NOT touch directories or non-jar files under plugins/
# - Builds desired jar set in temp dir, then swaps jars safely.
# ------------------------------------------------------------------------------

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
PLUGIN_LIB_ROOT="${ROOT_PATH}/libraries/plugins"
INSTANCES_ROOT="${ROOT_PATH}/servers"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: '$1'"; }

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
# Plugin Linking Logic
# ------------------------------------------------------------------------------

# Link plugins for a server instance
link_server_plugins() {
  local server_name="$1"
  local engine="$2"
  local instance_dir="$3"
  local tag="[${server_name}]"

  local dest_dir="${instance_dir}/plugins"
  local engine_lib_root="${PLUGIN_LIB_ROOT}/${engine}"
  local managed_lib_dir="${engine_lib_root}/Managed"

  mkdir -p "$dest_dir"

  # plugins config may be missing
  if ! jq -e ".servers[\"${server_name}\"].plugins? | type==\"object\"" "$CONFIG_FILE" >/dev/null 2>&1; then
    warn "${tag} No plugins configured. Skipping."

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
      warn "${tag} Unknown type '$type' for '${plugin_key}' (skipping)"
      continue
      ;;
    esac

    if [[ -n "${src_file:-}" && -f "$src_file" ]]; then
      ln -sfn "$src_file" "${temp_build_dir}/${plugin_key}.jar"
      echo -e "${GREEN}[LINK]${NC} ${tag} ${plugin_key}.jar -> $(basename "$src_file")"
      ((linked++)) || true
    else
      echo -e "${RED}[MISS]${NC} ${tag} ${plugin_key}.jar (pattern: ${pattern}) not found for engine=${engine}"
      ((missing++)) || true
    fi
  done

  # If nothing linked, preserve existing jars
  if [[ $linked -eq 0 ]]; then
    warn "${tag} No plugins linked. Preserving existing *.jar in ${dest_dir}"
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
    warn "${tag} Apply failed. Rolling back..."
    shopt -s nullglob

    for b in "$backup_dir"/*.jar; do
      mv -f "$b" "$dest_dir/" 2>/dev/null || true
    done
    shopt -u nullglob

    rm -rf "$backup_dir" 2>/dev/null || true
    die "${tag} Failed to apply plugins."
  fi

  # Cleanup backups (managed jars only)
  rm -rf "$backup_dir" 2>/dev/null || true

  if [[ $missing -gt 0 ]]; then
    warn "${tag} Linked with ${missing} missing plugin(s)."
  else
    info "${tag} All plugins linked."
  fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

need_cmd jq
need_cmd realpath
need_cmd find
need_cmd awk
need_cmd sort
need_cmd mktemp
need_cmd mv

# Check config file
[[ -f "$CONFIG_FILE" ]] || die "Config file missing: $CONFIG_FILE"

# Load configuration file
CONFIG="$(cat "$CONFIG_FILE")"

jq -e '.servers and (.servers | type=="object")' >/dev/null <<<"$CONFIG" ||
  die "Invalid config: expected '.servers' object in ${CONFIG_FILE}"

mapfile -t SERVERS < <(jq -r '.servers | keys[]' <<<"$CONFIG")

for SERVER in "${SERVERS[@]}"; do
  ENGINE="$(jq -r ".servers[\"$SERVER\"].engine // empty" <<<"$CONFIG")"
  SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"

  # Validate engine and server dir
  if [[ -z "$ENGINE" ]]; then
    warn "[${SERVER}] Missing engine in config. Skipping plugins."
    continue
  fi

  if [[ ! -d "$SERVER_DIR" ]]; then
    warn "[${SERVER}] Instance directory missing for '$SERVER'. Skipping plugins."
    continue
  fi

  echo "-----------------------------------------------------"
  echo -e "Linking Plugins: ${BLUE}${SERVER}${NC} (${ENGINE})"
  echo "-----------------------------------------------------"

  link_server_plugins "$SERVER" "$ENGINE" "$SERVER_DIR"
done

echo "-----------------------------------------------------"
echo -e "${GREEN}Plugin linking complete.${NC}"
