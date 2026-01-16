#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Get Engine (PaperMC Fill API v3)
# ------------------------------------------------------------------------------
# Downloads the latest build for each engine/version defined in config/update.json
# Atomic writes, parallel jobs, safe cleanup.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

# API Url & User Agent
FILL_API="https://fill.papermc.io/v3"
USER_AGENT="Everest/2.0.1 (https://github.com/67D48D5/Everest)"

# Download settings
CURL_RETRY=1
CURL_RETRY_DELAY=2
CURL_CONNECT_TIMEOUT=14

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

log_info() { echo -e "[$(date '+%H:%M:%S') ${GREEN}INFO${NC}] [get-engine]: $1"; }
log_warn() { echo -e "[$(date '+%H:%M:%S') ${YELLOW}WARN${NC}] [get-engine]: $1"; }
log_err() { echo -e "[$(date '+%H:%M:%S') ${RED}ERROR${NC}] [get-engine]: $1" >&2; }

url_basename() {
    local u="$1"
    printf '%s' "${u##*/}"
}

curl_json() {
    # stdout: JSON body, stderr: curl errors
    local url="$1"

    curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry "${CURL_RETRY}" \
        --retry-delay "${CURL_RETRY_DELAY}" \
        --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
        "$url"
}

# Ensure we don't leave background jobs running on interrupt
cleanup_jobs() {
    log_info "Interrupt detected. Killing background jobs..."
    local pids
    pids="$(jobs -pr || true)"
    if [[ -n "$pids" ]]; then
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_jobs SIGINT SIGTERM

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

# Check for required dependencies
for cmd in jq curl realpath; do
    command -v "$cmd" &>/dev/null || {
        log_err "'$cmd' not found"
        exit 1
    }
done

# Ensure config file and engine dir exist
[[ -f "$CONFIG_FILE" ]] || {
    log_err "Config file missing: ${CONFIG_FILE}"
    exit 1
}
mkdir -p "$ENGINE_DIR"

# ------------------------------------------------------------------------------
# Engine Processing Function
# ------------------------------------------------------------------------------

process_engine() {
    local raw_project="$1"
    local requested_version="$2"
    local project="${raw_project,,}" # lowercase
    local tag="${project} (${requested_version})"

    # 1. Version meta -> builds[]
    local version_url="${FILL_API}/projects/${project}/versions/${requested_version}"
    local version_response

    if ! version_response="$(curl_json "$version_url")"; then
        log_err "Failed to fetch version meta for ${tag}"

        return 1
    fi

    # API may return { ok:false, message:"..." }
    if jq -e '.ok == false' >/dev/null 2>&1 <<<"$version_response"; then
        local msg="$(jq -r '.message // "Unknown error"' <<<"$version_response")"

        log_err "API error for ${tag}: ${msg}"

        return 1
    fi

    local latest_build="$(jq -r '.builds | max // empty' <<<"$version_response")"

    if [[ -z "$latest_build" || "$latest_build" == "null" ]]; then
        log_warn "No builds found for ${tag}. Skipping."

        return 0
    fi

    # 2. Build detail -> downloads["server:default"].url/name
    local build_url="${FILL_API}/projects/${project}/versions/${requested_version}/builds/${latest_build}"
    local build_response

    if ! build_response="$(curl_json "$build_url")"; then
        log_err "Failed to fetch build detail for ${tag} (build=${latest_build})"

        return 1
    fi

    if jq -e '.ok == false' >/dev/null 2>&1 <<<"$build_response"; then
        local msg="$(jq -r '.message // "Unknown error"' <<<"$build_response")"

        # Specific case: build not found
        log_err "API error for ${tag} (build=${latest_build}): ${msg}"

        return 1
    fi

    local stable_url="$(jq -r '.downloads."server:default".url // empty' <<<"$build_response")"
    local stable_name="$(jq -r '.downloads."server:default".name // empty' <<<"$build_response")"

    if [[ -z "$stable_url" ]]; then
        log_warn "No download url in build detail for ${tag}. Skipping."

        return 0
    fi

    if [[ -z "$stable_name" || "$stable_name" == "null" ]]; then
        stable_name="$(url_basename "$stable_url")"
    fi

    local target_path="${ENGINE_DIR}/${stable_name}"

    # Robust up-to-date check:
    # If the exact filename for latest build already exists, we are done.
    if [[ -f "$target_path" ]]; then
        log_info "Up-to-date for ${tag} (build=${latest_build}, file=${stable_name})"

        return 0
    fi

    # 3. Download (atomic)
    local temp_file="${target_path}.tmp.$$"

    log_info "Downloading for ${tag}: ${stable_name} (build=${latest_build})..."

    if curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry "${CURL_RETRY}" \
        --retry-delay "${CURL_RETRY_DELAY}" \
        -o "$temp_file" \
        "$stable_url"; then

        # Move to final location
        mv -f "$temp_file" "$target_path"

        log_info "Downloaded for ${tag}: ${stable_name}"
    else
        # Cleanup temp file on failure
        rm -f "$temp_file"

        log_err "Download failed for ${tag}: ${stable_name}"

        return 1
    fi

    # 4. Cleanup old jars for the same project+requested_version only (safe)
    # Example: paper-1.20.4-*.jar
    # This avoids nuking other versions or other naming families.
    local pattern="${ENGINE_DIR}/${project}-${requested_version}-"*.jar
    local removed=0

    shopt -s nullglob

    # Iterate matching files
    for f in $pattern; do
        # Keep the current file we just downloaded (by exact name)
        if [[ "$(basename "$f")" == "$stable_name" ]]; then
            continue
        fi

        # Remove old file
        rm -f "$f"

        # Count cleanup
        ((removed++)) || true
    done

    shopt -u nullglob

    # Report cleanup
    if [[ $removed -gt 0 ]]; then
        log_warn "Removed ${removed} old build(s) for (${project} ${requested_version})"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Main Process Logic
# ------------------------------------------------------------------------------

log_info "Starting engine updates (Fill v3)..."

# Read config
CONFIG="$(cat "$CONFIG_FILE")"

# Validate config structure minimally
jq -e '.engines and (.engines | type=="object")' >/dev/null <<<"$CONFIG" ||
    {
        log_err "Invalid config: expected '.engines' object in ${CONFIG_FILE}"
        exit 1
    }

# Job tracking
declare -a JOB_PIDS=()
failed_jobs=0

# Launch parallel jobs
while IFS=$'\t' read -r engine version; do
    # Skip empty
    [[ -n "${engine:-}" && -n "${version:-}" ]] || continue

    # Launch job
    process_engine "$engine" "$version" &

    # Collect PID
    JOB_PIDS+=("$!")
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

# Wait
for pid in "${JOB_PIDS[@]}"; do
    if ! wait "$pid"; then
        # If a job failed, increment the counter
        ((failed_jobs++)) || true
    fi
done

# Final report
if [[ $failed_jobs -gt 0 ]]; then
    log_warn "${failed_jobs} engine(s) failed to update."
fi

log_info "All engines are up-to-date."
exit 0
