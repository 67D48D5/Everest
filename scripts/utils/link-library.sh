#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Link Library (Static Asset Manager)
# ------------------------------------------------------------------------------
# - Links resources from libraries/common into servers/<instance>
# - Uses simple path concatenation (original behavior)
# - No path normalization / No symlink resolution (keep it simple)
# ------------------------------------------------------------------------------

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
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

# ------------------------------------------------------------------------------
# Core: Link Resource Function
# ------------------------------------------------------------------------------

link_resource() {
    local source_path="$1"
    local dest_path="$2"
    local resource_name="$3"
    local tag="$4"

    if [[ ! -e "$source_path" ]]; then
        echo -e "${YELLOW}[WARN]${NC} ${tag} Source not found for '$resource_name': $source_path" >&2
        echo -e "${YELLOW}[WARN]${NC} ${tag} Creating empty directory for '$resource_name'" >&2
        mkdir -p "$source_path"
    fi

    mkdir -p "$(dirname "$dest_path")"

    if [[ -L "$dest_path" ]]; then
        rm -f "$dest_path"
    elif [[ -d "$dest_path" ]]; then
        warn "${tag} Replacing directory with symlink: $dest_path"
        rm -rf "$dest_path"
    elif [[ -f "$dest_path" ]]; then
        warn "${tag} Replacing file with symlink: $dest_path"
        rm -f "$dest_path"
    fi

    # Create symlink (force, no-dereference)
    ln -sfn "$source_path" "$dest_path"

    echo -e "${GREEN}[LINK]${NC} ${tag} ${resource_name} -> $dest_path"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

need_cmd jq
need_cmd realpath

# Check config file
[[ -f "$CONFIG_FILE" ]] || die "Config file missing: $CONFIG_FILE"

mkdir -p "$INSTANCES_ROOT"

# Load configuration file
CONFIG="$(cat "$CONFIG_FILE")"

jq -e '.servers and (.servers | type=="object")' >/dev/null <<<"$CONFIG" ||
    die "Invalid config: expected '.servers' object in ${CONFIG_FILE}"

# Get servers safely (no subshell loop)
mapfile -t SERVERS < <(jq -r '.servers | keys[]' <<<"$CONFIG")

for SERVER in "${SERVERS[@]}"; do
    ENGINE="$(jq -r ".servers[\"$SERVER\"].engine // \"unknown\"" <<<"$CONFIG")"
    SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"
    TAG="[${SERVER}]"

    if [[ ! -d "$SERVER_DIR" ]]; then
        warn "${TAG} Instance directory missing. Creating..."
        mkdir -p "$SERVER_DIR"
    fi

    echo "-----------------------------------------------------"
    echo -e "Processing Server: ${GREEN}${SERVER}${NC} (${ENGINE})"
    echo "-----------------------------------------------------"

    # libraries section optional
    if ! jq -e ".servers[\"$SERVER\"].libraries? | type==\"array\"" >/dev/null 2>&1 <<<"$CONFIG"; then
        info "${TAG} No libraries configured. Skipping."
        continue
    fi

    mapfile -t LIBS < <(jq -c ".servers[\"$SERVER\"].libraries[]?" <<<"$CONFIG")

    for library in "${LIBS[@]}"; do
        src="$(jq -r '.source // empty' <<<"$library")"
        dest="$(jq -r '.destination // empty' <<<"$library")"
        name="$(jq -r '.name // empty' <<<"$library")"

        [[ -n "$src" && -n "$dest" && -n "$name" ]] || die "${TAG} Invalid library entry: $library"

        FULL_SRC="${COMMON_ROOT}/${src}"
        FULL_DEST="${SERVER_DIR}/${dest}"

        link_resource "$FULL_SRC" "$FULL_DEST" "$name" "$TAG"
    done
done

echo "-----------------------------------------------------"
echo -e "${GREEN}Library linking complete.${NC}"
