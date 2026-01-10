#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Get Plugin - Dynamic Plugin Downloader for Everest
# ------------------------------------------------------------------------------

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
PLUGIN_LIB_ROOT="${ROOT_PATH}/libraries/plugins"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Initialization & Cleanup
# ------------------------------------------------------------------------------

# Cleanup function for temp directories
declare -a TEMP_DIRS=()
cleanup() {
    local exit_code=$?
    if [[ -n "$(jobs -p)" ]]; then kill $(jobs -p) 2>/dev/null || true; fi
    if [[ ${#TEMP_DIRS[@]} -gt 0 ]]; then
        for temp_dir in "${TEMP_DIRS[@]}"; do
            [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
        done
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# URL Resolvers (Keep existing resolvers: Jenkins, GitHub, EngineHub)
# ------------------------------------------------------------------------------
resolve_jenkins() {
    local url="${1%/}" key="$2" api meta rel final
    api="${url}/lastSuccessfulBuild/api/json"
    if ! meta=$(curl -fsSL --retry 3 --connect-timeout 10 "$api"); then return 1; fi
    rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" | grep -Ei "${key}.*\.jar$" | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" | grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && return 1
    echo "${url}/lastSuccessfulBuild/artifact/$rel"
}

resolve_github() {
    local url="$1" repo api_url resp asset_url
    repo=$(sed -E 's|https://github.com/([^/]+/[^/]+).*|\1|' <<<"$url")
    api_url="https://api.github.com/repos/$repo/releases/latest"
    if ! resp=$(curl -fsSL --retry 3 --connect-timeout 10 "$api_url"); then return 1; fi
    asset_url=$(jq -r '.assets[].browser_download_url' <<<"$resp" | grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$asset_url" ]] && return 1
    echo "$asset_url"
}

resolve_enginehub() {
    local url="$1" final_url html jar_url
    final_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "$url")
    [[ -z "$final_url" ]] && return 1
    if ! html=$(curl -fsSL --retry 3 --connect-timeout 10 "$final_url"); then return 1; fi
    jar_url=$(grep -Eo 'https://ci\.enginehub\.org/repository/download/[^"]+\.jar\?[^"]+' <<<"$html" | head -n1)
    [[ -z "$jar_url" ]] && return 1
    echo "${jar_url//&amp;/&}"
}

# ------------------------------------------------------------------------------
# Core Logic: Download Single Plugin
# ------------------------------------------------------------------------------
download_plugin() {
    local engine="$1"
    local name="$2"
    local url="$3"
    local dest_dir="$4"
    local resolved_url="$url"
    local resolver_name=""

    if [[ -z "$url" ]]; then return 0; fi

    if [[ "$url" == https://builds.enginehub.org/job/* && "$url" != *.jar ]]; then
        resolver_name="EngineHub"
    elif [[ "$url" == *"/job/"* && "$url" != *.jar ]]; then
        resolver_name="Jenkins"
    elif [[ "$url" == https://github.com/*/releases* && "$url" != *.jar ]]; then
        resolver_name="GitHub"
    fi

    if [[ -n "$resolver_name" ]]; then
        echo -e "${PURPLE}[RESOLVE]${NC} $name ($resolver_name)..."
        local resolve_result=""
        case "$resolver_name" in
        EngineHub) resolve_result=$(resolve_enginehub "$url") ;;
        Jenkins) resolve_result=$(resolve_jenkins "$url" "$engine") ;;
        GitHub) resolve_result=$(resolve_github "$url") ;;
        esac
        if [[ -n "$resolve_result" ]]; then
            resolved_url="$resolve_result"
        else
            echo -e "${RED}[ERROR]${NC} Failed to resolve URL for '$name'"
            return 1
        fi
    fi

    local filename
    filename=$(basename "${resolved_url%%\?*}")
    if [[ "$filename" != *.jar ]]; then
        filename="${name}.jar"
    fi

    echo -e "${BLUE}[DOWN]${NC} Downloading '$name'..."
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$dest_dir/$filename" "$resolved_url"; then
        echo -e "${GREEN}[DONE]${NC} Downloaded '$name ($filename)'"
    else
        echo -e "${RED}[FAIL]${NC} Download failed for '$name'"
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

# Iterate Engines (velocity, paper...)
jq -r '.plugins | keys[]' <<<"$CONFIG" | while read -r engine; do
    echo "-----------------------------------------------------"
    echo -e "Processing Engine: ${GREEN}${engine}${NC}"
    echo "-----------------------------------------------------"

    ENGINE_ROOT="${PLUGIN_LIB_ROOT}/${engine}"
    TARGET_FINAL_DIR="${ENGINE_ROOT}/Managed"

    # Temp dir creation
    mkdir -p "$ENGINE_ROOT"
    TEMP_DIR=$(mktemp -d -p "$ENGINE_ROOT" ".tmp_managed_XXXXXX")
    TEMP_DIRS+=("$TEMP_DIR")

    declare -a pids=()
    declare -a names=()

    # 1. Start Parallel Downloads
    while IFS=$'\t' read -r name url; do
        download_plugin "$engine" "$name" "$url" "$TEMP_DIR" &
        pids+=($!)
        names+=("$name")
    done < <(jq -r ".plugins[\"$engine\"] | to_entries[] | \"\(.key)\t\(.value)\"" <<<"$CONFIG")

    # 2. Wait and Handle Fallback
    failed_count=0
    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        name="${names[$i]}"

        if ! wait "$pid"; then
            ((failed_count++))
            echo -e "${YELLOW}[WARN] Attempting fallback for '$name'...${NC}"

            # [변경] Fallback 시 libraries/plugins/<engine>/Managed 에서 찾음
            if [[ -d "$TARGET_FINAL_DIR" ]]; then
                local found_backup=$(find "$TARGET_FINAL_DIR" -type f -name "*${name}*.jar" | head -n1)
                if [[ -n "$found_backup" ]]; then
                    cp -p "$found_backup" "$TEMP_DIR/"
                    echo -e "${GREEN}[RESTORE]${NC} Preserved previous version of '$name'"
                else
                    echo -e "${RED}[FAIL]${NC} No previous version found for fallback."
                fi
            fi
        fi
    done

    # 3. Atomic Swap
    if [[ $(ls -A "$TEMP_DIR") ]]; then
        echo -e "${BLUE}[SWAP]${NC} Updating 'Managed' directory for '$engine'..."

        mkdir -p "$(dirname "$TARGET_FINAL_DIR")"
        rm -rf "$TARGET_FINAL_DIR"
        mv "$TEMP_DIR" "$TARGET_FINAL_DIR"
    else
        echo -e "${YELLOW}[SKIP]${NC} No plugins downloaded/restored for '$engine'."
        rm -rf "$TEMP_DIR"
    fi
done

echo "-----------------------------------------------------"
echo -e "${GREEN}All plugin updates complete.${NC}"
