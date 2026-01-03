#!/usr/bin/env bash
set -euo pipefail

# Configuration
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and storage files are.
CONFIG_FILE="${ROOT_PATH}/config/server.json"
STORAGE_ROOT="${ROOT_PATH}/storage"
SERVERS_ROOT="${ROOT_PATH}/servers"

# Main Logic
# A reusable function to handle the creation of a symbolic link for data directories.
# It moves existing data to storage if it's a real directory, then creates a symlink.
# Arguments:
#   $1: Server name
#   $2: Data type (e.g., "logs", "world")
#   $3: Source path in the server directory
link_data() {
    local server_name="$1"
    local data_type="$2"
    local source_name="$3"

    local server_dir="${SERVERS_ROOT}/${server_name}"
    local storage_path="${STORAGE_ROOT}/${server_name}/${data_type}"
    local server_path="${server_dir}/${source_name}"

    # Ensure the storage directory exists.
    mkdir -p "$storage_path"

    # Check if the server path exists and handle it appropriately.
    if [[ -L "$server_path" ]]; then
        # Already a symlink, check if it points to the correct location.
        local current_target
        current_target="$(readlink -f "$server_path" 2>/dev/null || echo "")"
        if [[ "$current_target" == "$storage_path" ]]; then
            echo "[$(date '+%H:%M:%S') INFO] [link-data]: '$source_name' for '$server_name' is already correctly linked."
            return 0
        fi
        echo "[$(date '+%H:%M:%S') INFO] [link-data]: '$source_name' symlink for '$server_name' points elsewhere. Relinking."
        rm "$server_path"
    elif [[ -d "$server_path" ]]; then
        # It's a real directory, move its contents to storage.
        echo "[$(date '+%H:%M:%S') INFO] [link-data]: Moving existing '$source_name' data for '$server_name' to storage."
        # Use rsync for safe merging if storage already has data, otherwise mv.
        if [[ -n "$(ls -A "$server_path" 2>/dev/null)" ]]; then
            rsync -a --remove-source-files "$server_path/" "$storage_path/"
            # Remove empty directories left behind.
            find "$server_path" -type d -empty -delete 2>/dev/null || true
            # Remove the now-empty source directory if it still exists.
            [[ -d "$server_path" ]] && rmdir "$server_path" 2>/dev/null || true
        else
            rmdir "$server_path" 2>/dev/null || rm -rf "$server_path"
        fi
    elif [[ -f "$server_path" ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [link-data]: '$source_name' for '$server_name' is a file, not a directory. Skipping."
        return 1
    fi

    # Create the symlink.
    echo "[$(date '+%H:%M:%S') INFO] [link-data]: Linking '$source_name' for '$server_name': '$storage_path' -> '$server_path'"
    ln -sfn "$storage_path" "$server_path"
}

# Process a single server's data directories.
# Arguments:
#   $1: Server name
process_server() {
    local server_name="$1"
    local server_dir="${SERVERS_ROOT}/${server_name}"

    if [[ ! -d "$server_dir" ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [link-data]: Server directory '$server_dir' does not exist. Skipping."
        return 1
    fi

    echo "[$(date '+%H:%M:%S') INFO] [link-data]: Processing server '$server_name'..."

    # Link logs directory.
    link_data "$server_name" "logs" "logs"

    # Find and link world directories.
    # Common world directory patterns for Minecraft servers.
    local world_patterns=("world" "world_nether" "world_the_end")

    # Also detect custom world directories (e.g., wwild, wwild_nether, wwild_the_end).
    while IFS= read -r -d '' dir; do
        local dir_name
        dir_name="$(basename "$dir")"
        # Skip if it's a symlink (already processed) or a known non-world directory.
        if [[ -L "$dir" ]]; then
            continue
        fi
        # Check if this looks like a world directory (contains level.dat or region folder).
        if [[ -f "$dir/level.dat" ]] || [[ -d "$dir/region" ]]; then
            world_patterns+=("$dir_name")
        fi
    done < <(find "$server_dir" -maxdepth 1 -type d -print0 2>/dev/null)

    # Remove duplicates and process each world.
    local -A seen_worlds=()
    for world_name in "${world_patterns[@]}"; do
        if [[ -z "${seen_worlds[$world_name]:-}" ]]; then
            seen_worlds["$world_name"]=1
            local world_path="${server_dir}/${world_name}"
            # Only process if it exists (as dir or symlink) or matches a known pattern.
            if [[ -d "$world_path" ]] || [[ -L "$world_path" ]] || [[ "$world_name" =~ ^world ]]; then
                link_data "$server_name" "worlds/${world_name}" "$world_name"
            fi
        fi
    done

    echo "[$(date '+%H:%M:%S') INFO] [link-data]: Finished processing server '$server_name'."
}

# Execution
# Ensure jq is available for parsing JSON.
if ! command -v jq &>/dev/null; then
    echo "[$(date '+%H:%M:%S') ERROR] [link-data]: 'jq' is required but not installed." >&2
    exit 1
fi

# Check if config file exists.
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$(date '+%H:%M:%S') ERROR] [link-data]: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Create storage root directory.
mkdir -p "$STORAGE_ROOT"

echo "[$(date '+%H:%M:%S') INFO] [link-data]: Starting data linking process..."
echo "[$(date '+%H:%M:%S') INFO] [link-data]: Storage root: $STORAGE_ROOT"

# Get list of servers from config.
mapfile -t servers < <(jq -r '.servers | keys[]' "$CONFIG_FILE")

if [[ ${#servers[@]} -eq 0 ]]; then
    echo "[$(date '+%H:%M:%S') WARN] [link-data]: No servers found in configuration."
    exit 0
fi

# Process each server.
for server_name in "${servers[@]}"; do
    process_server "$server_name" || true
done

echo "[$(date '+%H:%M:%S') INFO] [link-data]: Data linking complete."
