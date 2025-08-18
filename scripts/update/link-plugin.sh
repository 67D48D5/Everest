#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and library files are.
CONFIG_FILE="${ROOT_PATH}/config/server.json"
PLUGIN_ROOT="${ROOT_PATH}/libraries/plugins"
SERVERS_ROOT="${ROOT_PATH}/servers"

# --- Helper Functions ---
# Find the latest file matching a pattern in a directory.
# This function is great, no changes needed here.
pick_latest() { # <dir> <glob>
  local dir="$1" pattern="$2"
  find "$dir" -maxdepth 1 -type f -iname "$pattern" 2>/dev/null | sort -V | tail -n1
}

# --- Main Logic ---
# A reusable function to handle linking all plugins for a single server.
# This uses an "atomic swap" method for safety, ensuring the server is never
# left with an incomplete or empty plugin directory.
link_server_plugins() {
  local server_name="$1"
  local engine="$2"
  local server_dir="$3"

  local dest_dir="${server_dir}/plugins"
  local auto_dir="${PLUGIN_ROOT}/${engine}/auto"
  local static_dir="${PLUGIN_ROOT}/${engine}"

  # --- The Atomic Swap: Part 1 ---
  # Create a secure, temporary directory to build the new plugin set.
  # We create it next to the real plugins/ dir to ensure it's on the same filesystem.
  mkdir -p "$server_dir"
  local temp_plugins_dir
  temp_plugins_dir=$(mktemp -d -p "$server_dir")
  echo "[$(date '+%H:%M:%S') INFO] [link-plugin]: Building new plugin set in: $(basename "$temp_plugins_dir")"

  # --- Plugin Linking Loop ---
  # Use process substitution to avoid subshells and ensure robustness.
  while IFS=$'\t' read -r plugin spec; do
    local scheme="${spec%%://*}"
    local pattern="${spec#*://}"
    local src_file=""

    case "$scheme" in
    auto) src_file=$(pick_latest "$auto_dir" "$pattern") ;;
    manual) src_file=$(pick_latest "$static_dir" "$pattern") ;;
    *)
      echo "[$(date '+%H:%M:%S') WARN] [link-plugin]: Unknown scheme '$scheme' for '$plugin'. Skipping." >&2
      continue
      ;;
    esac

    if [[ -n "${src_file:-}" && -f "$src_file" ]]; then
      # Link into the temporary directory, not the live one.
      ln -sf "$src_file" "${temp_plugins_dir}/${plugin}.jar"
      printf "[$(date '+%H:%M:%S') INFO] [link-plugin]: %-22s → %s\n" "${plugin}.jar" "$(basename "$src_file")"
    else
      printf "[$(date '+%H:%M:%S') WARN] [link-plugin]: %-22s NOT found (pattern: %s)\n" "$plugin" "$pattern" >&2
    fi
  done < <(jq -r ".servers[\"$server_name\"].plugins | to_entries[] | \"\(.key)\t\(.value)\"" <<<"$CONFIG")

  # --- The Atomic Swap: Part 2 ---
  # Once all links are created in the temp dir, swap it with the live one.
  # This is an instantaneous operation.
  echo "[$(date '+%H:%M:%S') INFO] [link-plugin]: Swapping plugin directories..."
  rm -rf "$dest_dir"/*.jar || true
  mv "$temp_plugins_dir"/*.jar "$dest_dir"
  rm -rf "$temp_plugins_dir"
}

# --- Execution ---
# Load the configuration file once.
CONFIG="$(cat "$CONFIG_FILE")"

# Use process substitution for the main server loop to keep it robust.
while read -r SERVER; do
  ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
  SERVER_DIR="${SERVERS_ROOT}/${SERVER}"

  echo "[$(date '+%H:%M:%S') INFO] [link-plugin]: Processing plugins for server: '${SERVER}' (engine: ${ENGINE})"

  # Call our main function to handle the linking logic.
  link_server_plugins "$SERVER" "$ENGINE" "$SERVER_DIR"

done < <(jq -r '.servers | keys[]' <<<"$CONFIG")

echo "[$(date '+%H:%M:%S') INFO] [link-plugin]: Plugin linking complete."
