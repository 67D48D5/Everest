#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Link Plugin - Dynamic Plugin Manager for Everest
# ------------------------------------------------------------------------------

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

pick_latest() { # <dir> <glob>
  local dir="$1" pattern="$2"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -type f -iname "$pattern" 2>/dev/null | sort -V | tail -n1
  else
    echo ""
  fi
}

# ------------------------------------------------------------------------------
# Core Logic: Link Plugins for Single Server
# ------------------------------------------------------------------------------
link_server_plugins() {
  local server_name="$1"
  local engine="$2"
  local instance_dir="$3"

  local dest_dir="${instance_dir}/plugins"

  local engine_lib_root="${PLUGIN_LIB_ROOT}/${engine}" # e.g. libraries/plugins/paper
  local managed_lib_dir="${engine_lib_root}/Managed"   # e.g. libraries/plugins/paper/Managed

  # Temp dir
  mkdir -p "$dest_dir"
  local temp_build_dir
  temp_build_dir=$(mktemp -d -p "$instance_dir" ".plugins_build_XXXXXX")

  while IFS=$'\t' read -r plugin_key type pattern; do
    local src_file=""

    case "$type" in
    auto)
      # auto -> libraries/plugins/<engine>/Managed
      src_file=$(pick_latest "$managed_lib_dir" "$pattern")
      ;;
    manual)
      # manual -> libraries/plugins/<engine>
      src_file=$(pick_latest "$engine_lib_root" "$pattern")
      ;;
    *)
      echo -e "${YELLOW}[SKIP] Unknown type '$type' for $plugin_key${NC}"
      continue
      ;;
    esac

    if [[ -n "${src_file:-}" && -f "$src_file" ]]; then
      ln -sf "$src_file" "${temp_build_dir}/${plugin_key}.jar"
      echo -e "${GREEN}[LINK]${NC} ${plugin_key}.jar -> $(basename "$src_file")"
    else
      echo -e "${RED}[FAIL]${NC} ${plugin_key}.jar (Pattern: $pattern) - Not found in ${engine} libraries"
    fi

  done < <(jq -r ".servers[\"${server_name}\"].plugins | to_entries[] | \"\(.key)\t\(.value.type)\t\(.value.pattern)\"" "$CONFIG_FILE")

  # Apply Changes (Strict Mode)
  find "$dest_dir" -maxdepth 1 -name "*.jar" -delete
  if compgen -G "${temp_build_dir}/*.jar" >/dev/null; then
    mv "${temp_build_dir}"/*.jar "$dest_dir/"
  else
    echo -e "${YELLOW}[WARN] No plugins linked for ${server_name}.${NC}"
  fi
  rm -rf "$temp_build_dir"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}[ERROR] Config file missing: $CONFIG_FILE${NC}"
  exit 1
fi

CONFIG="$(cat "$CONFIG_FILE")"

jq -r '.servers | keys[]' <<<"$CONFIG" | while read -r SERVER; do
  ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
  SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"

  if [[ ! -d "$SERVER_DIR" ]]; then
    echo -e "${YELLOW}[WARN] Instance dir missing for '$SERVER'. Skipping plugins.${NC}"
    continue
  fi

  echo "-----------------------------------------------------"
  echo -e "Linking Plugins: ${BLUE}${SERVER}${NC} (${ENGINE})"
  echo "-----------------------------------------------------"

  link_server_plugins "$SERVER" "$ENGINE" "$SERVER_DIR"
done

echo "-----------------------------------------------------"
echo -e "${GREEN}Plugin linking complete.${NC}"
