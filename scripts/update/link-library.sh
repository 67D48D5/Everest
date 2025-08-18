#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and library files are.
CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
SERVERS_ROOT="${ROOT_PATH}/servers"

# --- Main Logic ---
# A reusable function to handle the creation of a symbolic link.
# It checks if the destination exists (as a link or directory) and cleans it up
# before creating the new, correct symbolic link.
# Arguments:
#   $1: Source path (what we are linking to)
#   $2: Destination path (where the link will be created)
#   $3: A friendly name for the resource being linked, for logging.
link_resource() {
    local source_path="$1"
    local dest_path="$2"
    local resource_name="$3"

    # Ensure the parent directory of our destination exists.
    mkdir -p "$(dirname "$dest_path")"
    # Ensure the source directory exists so we don't create broken links.
    mkdir -p "$source_path"

    # Check if the destination already exists and clean it up.
    if [[ -L "$dest_path" ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [link-library]: '$resource_name' is already a symlink. Removing old link."
        rm "$dest_path"
    elif [[ -d "$dest_path" ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [link-library]: '$resource_name' is a directory. Removing existing directory."
        rm -rf "$dest_path"
    elif [[ -f "$dest_path" ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [link-library]: '$resource_name' is a file. Removing existing file."
        rm -f "$dest_path"
    fi

    echo "[$(date '+%H:%M:%S') INFO] [link-library]: Linking '$resource_name' from '$source_path' to '$dest_path'"
    # Use -s (symbolic), -f (force/overwrite), -n (no-dereference/treat link as a file)
    ln -sfn "$source_path" "$dest_path"
}

# --- Execution ---
# Load the configuration file once.
CONFIG="$(cat "$CONFIG_FILE")"

# Iterate over each server defined in the config.
jq -r '.servers | keys[]' <<<"$CONFIG" | while read -r SERVER; do
    ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
    SERVER_DIR="${SERVERS_ROOT}/${SERVER}"

    echo
    echo "[$(date '+%H:%M:%S') INFO] [link-library]: Processing server: ${SERVER} (engine: ${ENGINE})"

    # --- Define links needed for all server types ---
    # This is an array of "SourceSubPath;DestSubPath;FriendlyName"
    common_links=(
        "plugins/LuckPerms/libs;plugins/LuckPerms/libs;LuckPerms Libs"
    )

    # --- Define links needed only for Paper servers ---
    paper_links=(
        "cache;cache;Paper Cache"
        "libraries;libraries;Paper Libraries"
        "versions;versions;Paper Versions"
        "plugins/.paper-remapped;plugins/.paper-remapped;Paper Remapped Plugins"
    )

    # --- Process links based on engine type ---
    if [[ "$ENGINE" == "paper" ]]; then
        # Combine common links and paper-specific links
        links_to_create=("${common_links[@]}" "${paper_links[@]}")
        for link_info in "${links_to_create[@]}"; do
            # Split the string by the semicolon delimiter
            IFS=';' read -r src dest name <<<"$link_info"
            link_resource "${COMMON_ROOT}/${src}" "${SERVER_DIR}/${dest}" "$name"
        done
    elif [[ "$ENGINE" == "velocity" ]]; then
        # Velocity has a special path for LuckPerms
        link_resource "${COMMON_ROOT}/plugins/LuckPerms/libs" "${SERVER_DIR}/plugins/luckperms/libs" "LuckPerms Libs"
    fi

done

echo
echo "[$(date '+%H:%M:%S') INFO] [link-library]: Common resource linking complete."
