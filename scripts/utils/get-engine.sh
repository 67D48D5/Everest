#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Get Engine (PaperMC Fill API v3)
# ------------------------------------------------------------------------------
# Downloads the latest build for each engine/version defined in config/update.json
# Atomic writes, parallel jobs, safe cleanup.
# ------------------------------------------------------------------------------

# Paths
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

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing dependency: '$1'"
}

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
    echo -e "\n${RED}[STOP]${NC} Interrupt detected. Killing background jobs..."
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
# Core: process one engine
# ------------------------------------------------------------------------------

process_engine() {
    local raw_project="$1"
    local requested_version="$2"
    local project="${raw_project,,}" # lowercase
    local tag="[${project}:${requested_version}]"

    # 1) Version meta -> builds[]
    local version_url="${FILL_API}/projects/${project}/versions/${requested_version}"
    local version_response
    if ! version_response="$(curl_json "$version_url")"; then
        echo -e "${RED}[FAIL]${NC} ${tag} Failed to fetch version meta" >&2
        return 1
    fi

    # API may return { ok:false, message:"..." }
    if jq -e '.ok == false' >/dev/null 2>&1 <<<"$version_response"; then
        local msg
        msg="$(jq -r '.message // "Unknown error"' <<<"$version_response")"
        echo -e "${RED}[FAIL]${NC} ${tag} API error: ${msg}" >&2
        return 1
    fi

    local latest_build
    latest_build="$(jq -r '.builds | max // empty' <<<"$version_response")"

    if [[ -z "$latest_build" || "$latest_build" == "null" ]]; then
        warn "${tag} No builds found. Skipping."
        return 0
    fi

    # 2) Build detail -> downloads["server:default"].url/name
    local build_url="${FILL_API}/projects/${project}/versions/${requested_version}/builds/${latest_build}"
    local build_response
    if ! build_response="$(curl_json "$build_url")"; then
        echo -e "${RED}[FAIL]${NC} ${tag} Failed to fetch build detail (build=${latest_build})" >&2
        return 1
    fi

    if jq -e '.ok == false' >/dev/null 2>&1 <<<"$build_response"; then
        local msg
        msg="$(jq -r '.message // "Unknown error"' <<<"$build_response")"
        echo -e "${RED}[FAIL]${NC} ${tag} API error (build=${latest_build}): ${msg}" >&2
        return 1
    fi

    local stable_url stable_name
    stable_url="$(jq -r '.downloads."server:default".url // empty' <<<"$build_response")"
    stable_name="$(jq -r '.downloads."server:default".name // empty' <<<"$build_response")"

    if [[ -z "$stable_url" ]]; then
        warn "${tag} No download url in build detail. Skipping."
        return 0
    fi

    if [[ -z "$stable_name" || "$stable_name" == "null" ]]; then
        stable_name="$(url_basename "$stable_url")"
    fi

    local target_path="${ENGINE_DIR}/${stable_name}"

    # Robust up-to-date check:
    # If the exact filename for latest build already exists, we are done.
    if [[ -f "$target_path" ]]; then
        ok "${tag} Up-to-date (build=${latest_build}, file=${stable_name})"
        return 0
    fi

    # 3) Download (atomic)
    local temp_file="${target_path}.tmp.$$"
    echo -e "${BLUE}[DOWN]${NC} ${tag} Downloading ${stable_name} (build=${latest_build})..."

    if curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry "${CURL_RETRY}" \
        --retry-delay "${CURL_RETRY_DELAY}" \
        -o "$temp_file" \
        "$stable_url"; then
        mv -f "$temp_file" "$target_path"
        ok "${tag} Downloaded ${stable_name}"
    else
        rm -f "$temp_file"
        echo -e "${RED}[FAIL]${NC} ${tag} Download failed (${stable_name})" >&2
        return 1
    fi

    # 4) Cleanup old jars for the same project+requested_version only (safe)
    # Example: paper-1.20.4-*.jar
    # This avoids nuking other versions or other naming families.
    local pattern="${ENGINE_DIR}/${project}-${requested_version}-"*.jar
    local removed=0

    shopt -s nullglob
    for f in $pattern; do
        # Keep the current file we just downloaded (by exact name)
        if [[ "$(basename "$f")" == "$stable_name" ]]; then
            continue
        fi
        rm -f "$f"
        ((removed++)) || true
    done
    shopt -u nullglob

    if [[ $removed -gt 0 ]]; then
        warn "${tag} Removed ${removed} old build(s) for ${project} ${requested_version}"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
need_cmd jq
need_cmd curl
need_cmd realpath

[[ -f "$CONFIG_FILE" ]] || die "Config file missing: ${CONFIG_FILE}"
mkdir -p "$ENGINE_DIR"

info "Starting engine updates (Fill v3)..."

# Read config
CONFIG="$(cat "$CONFIG_FILE")"

# Validate config structure minimally
jq -e '.engines and (.engines | type=="object")' >/dev/null <<<"$CONFIG" ||
    die "Invalid config: expected '.engines' object in ${CONFIG_FILE}"

declare -a JOB_PIDS=()
failed_jobs=0

# Launch parallel jobs
while IFS=$'\t' read -r engine version; do
    # Skip empty
    [[ -n "${engine:-}" && -n "${version:-}" ]] || continue
    process_engine "$engine" "$version" &
    JOB_PIDS+=("$!")
done < <(jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG")

# Wait
for pid in "${JOB_PIDS[@]}"; do
    if ! wait "$pid"; then
        ((failed_jobs++)) || true
    fi
done

if [[ $failed_jobs -gt 0 ]]; then
    die "${failed_jobs} engine(s) failed to update."
fi

ok "All engines are up-to-date."
