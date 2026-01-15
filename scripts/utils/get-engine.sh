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

# API Url & User Agent
FILL_API="https://fill.papermc.io/v3"
USER_AGENT="Everest/2.0.1 (https://github.com/67D48D5/Everest)"

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

# Small helper: basename from URL
url_basename() {
    local u="$1"
    printf '%s' "${u##*/}"
}

# ------------------------------------------------------------------------------
# Core Function: Process Engine (v3)
# ------------------------------------------------------------------------------
process_engine() {
    local raw_project="$1"
    local requested_version="$2"
    local project="${raw_project,,}"

    # 1) Get version meta (contains builds: [92,91,...])
    local version_url="${FILL_API}/projects/${project}/versions/${requested_version}"
    local version_response

    if ! version_response=$(curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry 3 --retry-delay 2 --connect-timeout 10 \
        "$version_url" 2>&1); then
        echo -e "${RED}[ERROR] Failed to fetch version meta for '$project' (${requested_version})${NC}"
        return 1
    fi

    if echo "$version_response" | jq -e '.ok == false' >/dev/null 2>&1; then
        local msg
        msg="$(echo "$version_response" | jq -r '.message // "Unknown error"')"
        echo -e "${RED}[ERROR] API error for '$project' (${requested_version}): ${msg}${NC}"
        return 1
    fi

    # 2) Pick latest build number (MAX)
    local latest_build
    latest_build="$(echo "$version_response" | jq -r '.builds | max // empty')"

    if [[ -z "$latest_build" || "$latest_build" == "null" ]]; then
        echo -e "${YELLOW}[WARN] No builds found for '$project' (${requested_version}).${NC}"
        return 0
    fi

    # 2-1) Skip if same build jar already exists in ENGINE_DIR (naming: project-version-build.jar)
    if ls "${ENGINE_DIR}/${project}-${requested_version}-"*.jar >/dev/null 2>&1; then
        # find any matching jar and compare last number
        local existing
        existing="$(ls -1 "${ENGINE_DIR}/${project}-${requested_version}-"*.jar | head -n 1)"
        local existing_build
        existing_build="$(basename "$existing" | sed -E 's/.*-([0-9]+)\.jar/\1/')"

        if [[ "$existing_build" == "$latest_build" ]]; then
            echo -e "${GREEN}[SKIP]${NC} ${project} ${requested_version} is already up-to-date (build=${latest_build})."
            return 0
        fi
    fi

    # 3) Fetch build detail for that build number
    local build_url="${FILL_API}/projects/${project}/versions/${requested_version}/builds/${latest_build}"
    local build_response

    if ! build_response=$(curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry 3 --retry-delay 2 --connect-timeout 10 \
        "$build_url" 2>&1); then
        echo -e "${RED}[ERROR] Failed to fetch build detail for '$project' (${requested_version}) build=${latest_build}${NC}"
        return 1
    fi

    if echo "$build_response" | jq -e '.ok == false' >/dev/null 2>&1; then
        local msg
        msg="$(echo "$build_response" | jq -r '.message // "Unknown error"')"
        echo -e "${RED}[ERROR] API error for '$project' (${requested_version}) build=${latest_build}: ${msg}${NC}"
        return 1
    fi

    # 4) Extract download url/name from build detail
    local stable_url stable_name
    stable_url="$(echo "$build_response" | jq -r '.downloads."server:default".url // empty')"
    stable_name="$(echo "$build_response" | jq -r '.downloads."server:default".name // empty')"

    if [[ -z "$stable_url" ]]; then
        echo -e "${YELLOW}[WARN] No download url in build detail for '$project' (${requested_version}) build=${latest_build}.${NC}"
        return 0
    fi

    # Derive filename if missing
    if [[ -z "$stable_name" || "$stable_name" == "null" ]]; then
        stable_name="$(url_basename "$stable_url")"
    fi

    local target_path="${ENGINE_DIR}/${stable_name}"
    local temp_file="${target_path}.tmp"

    echo -e "${BLUE}[DOWN]${NC} Downloading ${stable_name} (project=${project}, version=${requested_version})..."

    if curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry 3 --retry-delay 2 \
        -o "$temp_file" \
        "$stable_url"; then

        mv "$temp_file" "$target_path"
        echo -e "${GREEN}[DONE]${NC} Downloaded: ${stable_name}"

        # Cleanup old versions: remove project-*.jar except current name
        # This assumes Paper-like naming. If naming differs, adjust pattern per engine.
        local old_count=0
        while IFS= read -r old_file; do
            rm -f "$old_file"
            ((old_count += 1))
        done < <(find "$ENGINE_DIR" -maxdepth 1 -type f -name "${project}-*.jar" ! -name "$stable_name")

        if [[ $old_count -gt 0 ]]; then
            echo -e "${YELLOW}[CLEAN]${NC} Removed $old_count old version(s) of ${project}"
        fi

    else
        echo -e "${RED}[FAIL]${NC} Download failed for ${stable_name}"
        rm -f "$temp_file"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR] Config file missing: $CONFIG_FILE${NC}"
    exit 1
fi

CONFIG="$(cat "$CONFIG_FILE")"
declare -a JOB_PIDS=()

echo -e "${BLUE}[INFO] Starting engine updates (Fill v3)...${NC}"

# Start parallel jobs
while IFS=$'\t' read -r engine version; do
    process_engine "$engine" "$version" &
    JOB_PIDS+=($!)
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

failed_jobs=0
for pid in "${JOB_PIDS[@]}"; do
    if ! wait "$pid"; then
        ((failed_jobs++))
    fi
done

if [[ $failed_jobs -gt 0 ]]; then
    echo -e "${RED}[ERROR] $failed_jobs engine(s) failed to update.${NC}"
    exit 1
else
    echo -e "${GREEN}[SUCCESS] All engines are up-to-date.${NC}"
    exit 0
fi
