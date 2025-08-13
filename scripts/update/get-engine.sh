#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and downloaded files are.
CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

# --- Pre-flight Checks ---
# Let's make sure our toolshed is full before we start.
echo "[$(date '+%H:%M:%S') INFO]: Checking for required tools..."
for cmd in curl jq realpath; do
    if ! command -v "$cmd" >/dev/null; then
        echo "[$(date '+%H:%M:%S') ERROR]: Missing dependency: '$cmd'. Please install it first." >&2
        exit 1
    fi
done

# And make sure the config file actually exists.
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$(date '+%H:%M:%S') ERROR]: File 'update.json' not found at '$CONFIG_FILE'" >&2
    exit 1
fi

# Let's get that engine directory ready.
mkdir -p "$ENGINE_DIR"

# --- Main Logic ---
# This is the core function that handles a single engine.
# It checks, downloads, and cleans up.
process_engine() {
    local project="$1" version="$2"

    echo "[$(date '+%H:%M:%S') INFO]: Processing '$project' version '$version'..."

    # Let's ask the PaperMC API about the latest build.
    local api_url="https://api.papermc.io/v2/projects/$project/versions/$version/builds"
    local api_response
    api_response=$(curl -fsSL --retry 3 --retry-delay 5 "$api_url") || {
        echo "[$(date '+%H:%M:%S') ERROR]: API fetch failed for '$project' '$version'. Skipping." >&2
        return 1 # Return an error code
    }

    # Let's figure out the latest build number and the full filename.
    local latest_build
    latest_build=$(jq -r '.builds[-1].build' <<<"$api_response")

    # If jq fails to find a build, it returns "null". Let's handle that.
    if [[ "$latest_build" == "null" ]]; then
        echo "[$(date '+%H:%M:%S') WARN]: No builds found for '$project' version '$version'. Skipping." >&2
        return 0 # Not an error, just nothing to do.
    fi

    local jar_name="${project}-${version}-${latest_build}.jar"
    local target_path="$ENGINE_DIR/$jar_name"

    # --- The Smart Part: Skip if we already have it! ---
    if [[ -f "$target_path" ]]; then
        echo "[$(date '+%H:%M:%S') INFO]: Already have the latest version of '$project': $jar_name. Skipping."
        return 0
    fi

    # --- If we got here, it's time to download. ---
    local download_url="https://api.papermc.io/v2/projects/$project/versions/$version/builds/$latest_build/downloads/$jar_name"
    echo "[$(date '+%H:%M:%S') INFO]: Downloading '$jar_name'..."

    if curl -fsSL --retry 3 --retry-delay 5 -o "$target_path" "$download_url"; then
        echo "[$(date '+%H:%M:%S') INFO]: Downloaded to '$target_path'"

        # --- Safer Cleanup: Only delete old files AFTER a successful download ---
        echo "[$(date '+%H:%M:%S') INFO]: Cleaning up old versions of '$project'..."
        find "$ENGINE_DIR" -maxdepth 1 -type f -name "${project}-*.jar" ! -name "$jar_name" -delete
    else
        echo "[$(date '+%H:%M:%S') ERROR]: Download failed for '$jar_name'. Check the URL or your connection." >&2
        # Clean up the potentially empty/corrupted file from the failed download.
        rm -f "$target_path"
        return 1
    fi
}

# --- Execution ---
# Load the configuration once.
CONFIG="$(cat "$CONFIG_FILE")"

echo
echo "[$(date '+%H:%M:%S') INFO]: Processing all engines..."

# This process substitution `< <(...)` prevents the while loop from running
# in a subshell. This ensures the 'wait' command below is in the correct
# shell scope and will wait for all background jobs to finish.
while IFS=$'\t' read -r engine version; do
    # The '&' at the end runs the function in the background!
    process_engine "$engine" "$version" &
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

# This 'wait' will now correctly pause the script until every single
# 'process_engine' job that we started has finished.
wait

echo
echo "[$(date '+%H:%M:%S') INFO]: All engine updates are finished."
