#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
PLUGIN_ROOT="${ROOT_PATH}/libraries/plugins"
SERVERS_ROOT="${ROOT_PATH}/servers"

# Check if config file exists
[[ -f "$CONFIG_FILE" ]] || {
  echo "❌ server.json not found" >&2
  exit 1
}

# Check for required dependencies
for cmd in jq realpath; do
  command -v "$cmd" >/dev/null || {
    echo "❌ Missing dependency: $cmd" >&2
    exit 1
  }
done

# Load the configuration file
CONFIG="$(cat "$CONFIG_FILE")"

# Find the latest file matching a pattern in a directory
pick_latest() { # <dir> <glob>
  local dir="$1" pattern="$2"
  find "$dir" -maxdepth 1 -type f -iname "$pattern" 2>/dev/null | sort | tail -n1
}

# Iterate over servers in the config
jq -r '.servers | keys[]' <<<"$CONFIG" | while read -r SERVER; do
  ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
  DEST_DIR="${SERVERS_ROOT}/${SERVER}/plugins"
  AUTO_DIR="${PLUGIN_ROOT}/${ENGINE}/auto"
  STATIC_DIR="${PLUGIN_ROOT}/${ENGINE}"

  # Clean up old plugin jar links
  rm -rf "$DEST_DIR"/*.jar
  [[ -d "$DEST_DIR" ]] || mkdir -p "$DEST_DIR"
  echo "🔗 ${SERVER}  (engine: ${ENGINE})"

  jq -r ".servers[\"$SERVER\"].plugins | to_entries[] | \"\(.key)\t\(.value)\"" <<<"$CONFIG" |
    while IFS=$'\t' read -r PLUGIN SPEC; do
      SCHEME="${SPEC%%://*}"
      PATTERN="${SPEC#*://}"

      case "$SCHEME" in
      auto) SRC=$(pick_latest "$AUTO_DIR" "$PATTERN") ;;
      manual) SRC=$(pick_latest "$STATIC_DIR" "$PATTERN") ;;
      *)
        echo "  ⚠️ Unknown scheme '$SCHEME' for $PLUGIN"
        continue
        ;;
      esac

      if [[ -n "${SRC:-}" && -f "$SRC" ]]; then
        ln -sf "$SRC" "${DEST_DIR}/${PLUGIN}.jar"
        printf "  ✔ %-22s → %s\n" "${PLUGIN}.jar" "$(basename "$SRC")"
      else
        printf "  ⚠️ %-22s NOT found (pattern: %s)\n" "$PLUGIN" "$PATTERN" >&2
      fi
    done
  echo
done

echo "✅ Plugin linking complete."
