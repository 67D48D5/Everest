#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Link Library - Static Asset Manager for Everest
# ------------------------------------------------------------------------------

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")" # scripts/utils/ -> root

CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
INSTANCES_ROOT="${ROOT_PATH}/servers"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Function: Link Resource
# ------------------------------------------------------------------------------
link_resource() {
    local source_path="$1"
    local dest_path="$2"
    local resource_name="$3"

    # [Safety Check 1] Check if source exists
    if [[ ! -e "$source_path" ]]; then
        echo -e "${RED}[ERROR] Source not found for '$resource_name': $source_path${NC}"
        echo -e "${YELLOW} -> Please check 'libraries/common' or your 'server.json' paths.${NC}"
        return 1
    fi

    # [Safety Check 2] Create parent directory for destination
    mkdir -p "$(dirname "$dest_path")"

    # [Clean Up] Clean existing resource at destination
    if [[ -L "$dest_path" ]]; then
        # echo "Replacing symlink for $resource_name..."
        rm "$dest_path"
    elif [[ -d "$dest_path" ]]; then
        echo -e "${YELLOW}[WARN] Replacing directory with symlink: $dest_path${NC}"
        rm -rf "$dest_path"
    elif [[ -f "$dest_path" ]]; then
        echo -e "${YELLOW}[WARN] Replacing file with symlink: $dest_path${NC}"
        rm -f "$dest_path"
    fi

    # [Link] Create symbolic link
    # -s: symbolic, -f: force, -n: no dereference
    ln -sfn "$source_path" "$dest_path"
    echo -e "${GREEN}[LINK]${NC} Created symlink for ${GREEN}$resource_name${NC} -> $dest_path${NC}"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR] Config file missing: $CONFIG_FILE${NC}"
    exit 1
fi

CONFIG="$(cat "$CONFIG_FILE")"

# Iterate over servers
jq -r '.servers | keys[]' <<<"$CONFIG" | while read -r SERVER; do
    ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
    SERVER_DIR="${INSTANCES_ROOT}/${SERVER}"

    # If the instance folder doesn't exist, warn and create it.
    if [[ ! -d "$SERVER_DIR" ]]; then
        echo -e "${YELLOW}[WARN] Instance directory missing for '$SERVER'. Creating...${NC}"
        mkdir -p "$SERVER_DIR"
    fi

    echo "-----------------------------------------------------"
    echo -e "Processing Server: ${GREEN}${SERVER}${NC} (${ENGINE})"
    echo "-----------------------------------------------------"

    # Process library links
    jq -c ".servers[\"$SERVER\"].libraries[]? // empty" <<<"$CONFIG" | while read -r library; do
        src=$(jq -r '.source' <<<"$library")
        dest=$(jq -r '.destination' <<<"$library")
        name=$(jq -r '.name' <<<"$library")

        # libraries/common + source path
        FULL_SRC="${COMMON_ROOT}/${src}"
        FULL_DEST="${SERVER_DIR}/${dest}"

        link_resource "$FULL_SRC" "$FULL_DEST" "$name"
    done
done

echo "-----------------------------------------------------"
echo -e "${GREEN}Library linking complete.${NC}"
