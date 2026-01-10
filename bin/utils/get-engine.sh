#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Get Engine - PaperMC API Downloader for Everest
# ------------------------------------------------------------------------------

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------------------

# Ensure directories exist
mkdir -p "$ENGINE_DIR"

# Trap for cleanup (Ctrl+C interrupt also terminates background jobs)
cleanup_jobs() {
    echo -e "\n${RED}[STOP] Interrupt detected. Killing background jobs...${NC}"
    kill $(jobs -p) 2>/dev/null || true
    exit 1
}
trap cleanup_jobs SIGINT SIGTERM

# ------------------------------------------------------------------------------
# Core Function: Process Engine
# ------------------------------------------------------------------------------
process_engine() {
    local raw_project="$1"
    local version="$2"

    # The API requires the project name in lowercase (Paper, Velocity...)
    local project="${raw_project,,}"

    # 1. Fetch Build List
    local api_url="https://api.papermc.io/v2/projects/${project}/versions/${version}/builds"
    local api_response

    # Retry if curl fails
    if ! api_response=$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$api_url" 2>&1); then
        echo -e "${RED}[ERROR] Failed to fetch builds for '$project' ($version)${NC}"
        return 1
    fi

    # 2. Extract Latest Build Info
    local latest_build application_name
    latest_build=$(jq -r '.builds[-1].build // empty' <<<"$api_response")
    application_name=$(jq -r '.builds[-1].downloads.application.name // empty' <<<"$api_response")

    if [[ -z "$latest_build" || -z "$application_name" ]]; then
        echo -e "${YELLOW}[WARN] No builds found for '$project' ($version). Check version in update.json.${NC}"
        return 0
    fi

    local target_path="${ENGINE_DIR}/${application_name}"

    # 3. Check Consistency
    if [[ -f "$target_path" ]]; then
        # If file exists, check if it's the latest
        echo -e "${GREEN}[SKIP]${NC} The $application_name is already up-to-date."
        return 0
    fi

    # 4. Download
    local download_url="https://api.papermc.io/v2/projects/${project}/versions/${version}/builds/${latest_build}/downloads/${application_name}"
    local temp_file="${target_path}.tmp"

    echo -e "${BLUE}[DOWN]${NC} Downloading $application_name..."

    if curl -fsSL --retry 3 --retry-delay 2 -o "$temp_file" "$download_url"; then
        mv "$temp_file" "$target_path"
        echo -e "${GREEN}[DONE]${NC} Downloaded: $application_name"

        # 5. Cleanup Old Versions
        # Remove all files matching "project-*.jar" pattern except the one just downloaded
        local old_count=0
        while IFS= read -r old_file; do
            rm -f "$old_file"
            ((old_count += 1))
        done < <(find "$ENGINE_DIR" -maxdepth 1 -type f -name "${project}-*.jar" ! -name "$application_name")

        if [[ $old_count -gt 0 ]]; then
            echo -e "${YELLOW}[CLEAN]${NC} Removed $old_count old version(s) of $project"
        fi
    else
        echo -e "${RED}[FAIL] Download failed for $application_name${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR] Config file missing: $CONFIG_FILE${NC}"
    exit 1
fi

CONFIG="$(cat "$CONFIG_FILE")"
declare -a JOB_PIDS=()

echo -e "${BLUE}[INFO] Starting engine updates...${NC}"

# Start Parallel Jobs
while IFS=$'\t' read -r engine version; do
    process_engine "$engine" "$version" &
    JOB_PIDS+=($!)
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

# Wait for all jobs
failed_jobs=0
for pid in "${JOB_PIDS[@]}"; do
    if ! wait "$pid"; then
        ((failed_jobs++))
    fi
done

# Final Report
if [[ $failed_jobs -gt 0 ]]; then
    echo -e "${RED}[ERROR] $failed_jobs engine(s) failed to update.${NC}"
    exit 1
else
    echo -e "${GREEN}[SUCCESS] All engines are up-to-date.${NC}"
    exit 0
fi
