#!/usr/bin/env bash
set -euo pipefail

# Configuration
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and downloaded files are.
CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

# Pre-flight Checks
# Let's get that engine directory ready.
mkdir -p "$ENGINE_DIR"

# Main Logic
# This is the core function that handles a single engine.
# It checks, downloads, and cleans up.
process_engine() {
    local project="$1" version="$2"

    echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Processing '$project' version '$version'..."

    # Query the PaperMC API for available builds
    local api_url="https://api.papermc.io/v2/projects/$project/versions/$version/builds"
    local api_response
    if ! api_response=$(curl -fsSL --retry 3 --retry-delay 5 "$api_url" 2>&1); then
        echo "[$(date '+%H:%M:%S') ERROR] [get-engine]: Failed to fetch builds for '$project' v$version" >&2
        echo "[$(date '+%H:%M:%S') ERROR] [get-engine]: API URL: $api_url" >&2
        return 1
    fi

    # Extract the latest build number and application name
    local latest_build application_name
    latest_build=$(jq -r '.builds[-1].build // empty' <<<"$api_response")
    application_name=$(jq -r '.builds[-1].downloads.application.name // empty' <<<"$api_response")

    if [[ -z "$latest_build" || -z "$application_name" ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [get-engine]: No builds available for '$project' v$version" >&2
        return 0
    fi

    local target_path="$ENGINE_DIR/$application_name"

    # Skip if we already have the latest version
    if [[ -f "$target_path" ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Already up-to-date: $application_name"
        return 0
    fi

    # Download the latest build
    local download_url="https://api.papermc.io/v2/projects/$project/versions/$version/builds/$latest_build/downloads/$application_name"
    echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Downloading $application_name..."

    local temp_file="${target_path}.tmp"
    if curl -fsSL --retry 3 --retry-delay 5 -o "$temp_file" "$download_url" 2>&1; then
        # Atomic move to final destination
        mv "$temp_file" "$target_path"
        echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Downloaded: $application_name"

        # Clean up old versions after successful download
        local old_count=0
        while IFS= read -r old_file; do
            rm -f "$old_file"
            ((old_count++))
        done < <(find "$ENGINE_DIR" -maxdepth 1 -type f -name "${project}-*.jar" ! -name "$application_name")

        if [[ $old_count -gt 0 ]]; then
            echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Removed $old_count old version(s) of '$project'"
        fi
    else
        echo "[$(date '+%H:%M:%S') ERROR] [get-engine]: Download failed for $application_name" >&2
        rm -f "$temp_file"
        return 1
    fi
}

# Execution
# Load the configuration once.
CONFIG="$(cat "$CONFIG_FILE")"

echo "[$(date '+%H:%M:%S') INFO] [get-engine]: Processing all engines..."

# Track background job PIDs for better error handling
declare -a JOB_PIDS=()

# This process substitution `< <(...)` prevents the while loop from running
# in a subshell. This ensures the 'wait' command below is in the correct
# shell scope and will wait for all background jobs to finish.
while IFS=$'\t' read -r engine version; do
    # The '&' at the end runs the function in the background!
    process_engine "$engine" "$version" &
    JOB_PIDS+=($!)
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

# This 'wait' will now correctly pause the script until every single
# 'process_engine' job that we started has finished.
# Track if any jobs failed
failed_jobs=0
for pid in "${JOB_PIDS[@]}"; do
    if ! wait "$pid"; then
        ((failed_jobs++))
    fi
done

if [[ $failed_jobs -gt 0 ]]; then
    echo "[$(date '+%H:%M:%S') WARN] [get-engine]: $failed_jobs engine(s) failed to update." >&2
fi

echo "[$(date '+%H:%M:%S') INFO] [get-engine]: All engine updates are finished."
