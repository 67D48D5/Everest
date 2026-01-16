#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Link Library (Static Asset Manager)
# ------------------------------------------------------------------------------
# - Links resources from libraries/common into servers/<instance>
# - Uses simple path concatenation (original behavior)
# - No path normalization / No symlink resolution (keep it simple)
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
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

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

# Make sure we have the tools we need.
for cmd in jq realpath ln rm; do
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

# Ensure common root exists
mkdir -p "$INSTANCES_ROOT"

# ------------------------------------------------------------------------------
# Core: Link Resource Function
# ------------------------------------------------------------------------------

link_resource() {
    local source_path="$1"
    local dest_path="$2"
    local resource_name="$3"
    local tag="$4"

    if [[ ! -e "$source_path" ]]; then
        log_warn "Source not found for ${tag}, '$resource_name': $source_path"
        log_warn "Creating empty directory for ${tag}, '$resource_name'"

        mkdir -p "$source_path"
    fi

    mkdir -p "$(dirname "$dest_path")"

    if [[ -L "$dest_path" ]]; then
        rm -f "$dest_path"
    elif [[ -d "$dest_path" ]]; then
        log_warn "Replacing directory with symlink for ${tag}: $dest_path"

        rm -rf "$dest_path"
    elif [[ -f "$dest_path" ]]; then
        log_warn "Replacing file with symlink for ${tag}: $dest_path"

        rm -f "$dest_path"
    fi

    # Create symlink (force, no-dereference)
    ln -sfn "$source_path" "$dest_path"

    log_info "${tag} ${resource_name} -> $dest_path"
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
    ENGINE="$(jq -r ".servers[\"$SERVER\"].engine // \"unknown\"" <<<"$CONFIG")"
    SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"

    if [[ ! -d "$SERVER_DIR" ]]; then
        log_warn "Instance directory missing for ${SERVER}. Creating..."

        mkdir -p "$SERVER_DIR"
    fi

    log_info "Processing Server: ${GREEN}${SERVER}${NC} (${ENGINE})"

    # Libraries section optional
    if ! jq -e ".servers[\"$SERVER\"].libraries? | type==\"array\"" >/dev/null 2>&1 <<<"$CONFIG"; then
        log_info "No libraries configured for ${SERVER}. Skipping."
        continue
    fi

    mapfile -t LIBS < <(jq -c ".servers[\"$SERVER\"].libraries[]?" <<<"$CONFIG")

    for library in "${LIBS[@]}"; do
        src="$(jq -r '.source // empty' <<<"$library")"
        dest="$(jq -r '.destination // empty' <<<"$library")"
        name="$(jq -r '.name // empty' <<<"$library")"

        [[ -n "$src" && -n "$dest" && -n "$name" ]] || {
            log_err "Invalid library entry: $library"

            continue
        }

        FULL_SRC="${COMMON_ROOT}/${src}"
        FULL_DEST="${SERVER_DIR}/${dest}"

        link_resource "$FULL_SRC" "$FULL_DEST" "$name" "$SERVER"
    done
done

log_info "Library linking complete."
exit 0
