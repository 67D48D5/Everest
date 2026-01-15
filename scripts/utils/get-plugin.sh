#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Get Plugin (Dynamic Plugin Downloader)
# ------------------------------------------------------------------------------
# - Resolves CI/GitHub URLs to a direct .jar URL (Jenkins / GitHub / EngineHub)
# - Downloads plugins in parallel per engine
# - Fallback: preserves previous version if download fails
# - Atomic swap of Managed directory
# ------------------------------------------------------------------------------

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../../")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
PLUGIN_LIB_ROOT="${ROOT_PATH}/libraries/plugins"

# User Agent
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
PURPLE=$'\033[0;35m'
NC=$'\033[0m'

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: '$1'"; }

# Global temp dirs for cleanup
declare -a TEMP_DIRS=()

cleanup() {
    local exit_code=$?
    local pids

    pids="$(jobs -pr || true)"

    if [[ -n "$pids" ]]; then
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null || true
    fi

    for d in "${TEMP_DIRS[@]}"; do
        [[ -d "$d" ]] && rm -rf "$d"
    done

    exit "$exit_code"
}

trap cleanup EXIT INT TERM

curl_json() {
    local url="$1"

    curl -fsSL \
        -H "User-Agent: ${USER_AGENT}" \
        --retry "${CURL_RETRY}" \
        --retry-delay "${CURL_RETRY_DELAY}" \
        --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
        "$url"
}

# ------------------------------------------------------------------------------
# URL Resolvers
# If you need other engine resolvers, add them here.
# If you prefer specific engine then modify the priority order in download_plugin().
# ------------------------------------------------------------------------------

resolve_jenkins() {
    local engine="$1" url="${2%/}" api meta rel

    api="${url}/lastSuccessfulBuild/api/json"
    meta="$(curl_json "$api")" || return 1

    # List artifacts and pick jar
    local rels

    rels="$(jq -r '.artifacts[].relativePath' <<<"$meta" |
        grep -Ei '\.jar$' |
        grep -viE '(-sources|-javadoc)\.jar$' || true)"

    [[ -n "$rels" ]] || return 1

    # Engine-aware preference
    if [[ "$engine" == "velocity" ]]; then
        rel="$(grep -Ei '(velocity)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(bungee|waterfall)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(all|universal)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -viE '(paper|bukkit|spigot)' <<<"$rels" | head -n1 || true)"
    else
        rel="$(grep -Ei '(paper)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(spigot|bukkit)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(all|universal)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -viE '(velocity|bungee|waterfall)' <<<"$rels" | head -n1 || true)"
    fi

    [[ -z "$rel" ]] && rel="$(head -n1 <<<"$rels")"
    [[ -z "$rel" ]] && return 1

    echo "${url}/lastSuccessfulBuild/artifact/$rel"
}

resolve_github() {
    local engine="$1" url="$2"
    local repo api_url resp
    local rels=""

    repo="$(sed -E 's|https://github.com/([^/]+/[^/]+).*|\1|' <<<"$url")"
    api_url="https://api.github.com/repos/$repo/releases/latest"

    resp="$(curl_json "$api_url")" || return 1

    # Collect jar urls
    local urls
    urls="$(jq -r '.assets[].browser_download_url' <<<"$resp" |
        grep -Ei '\.jar$' |
        grep -viE '(-sources|-javadoc)\.jar$' || true)"

    [[ -n "$urls" ]] || return 1

    # Engine-aware preference
    local preferred=""
    if [[ "$engine" == "velocity" ]]; then
        rel="$(grep -Ei '(velocity)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(bungee|waterfall)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(all|universal)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -viE '(paper|bukkit|spigot)' <<<"$rels" | head -n1 || true)"
    else
        rel="$(grep -Ei '(paper)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(spigot|bukkit)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -Ei '(all|universal)' <<<"$rels" | head -n1 || true)"
        [[ -z "$rel" ]] && rel="$(grep -viE '(velocity|bungee|waterfall)' <<<"$rels" | head -n1 || true)"
    fi

    # Universal/all-platform fallback
    [[ -z "$preferred" ]] && preferred="$(grep -Ei '(all|universal|platform)' <<<"$urls" | head -n1 || true)"
    [[ -z "$preferred" ]] && preferred="$(head -n1 <<<"$urls")"

    [[ -n "$preferred" ]] || return 1

    echo "$preferred"
}

resolve_enginehub() {
    local url="$1" final_url html jar_url

    final_url="$(curl -Ls -o /dev/null -w '%{url_effective}' "$url")" || return 1
    [[ -z "$final_url" ]] && return 1

    html="$(curl_json "$final_url")" || return 1
    jar_url="$(grep -Eo 'https://ci\.enginehub\.org/repository/download/[^"]+\.jar\?[^"]+' <<<"$html" | head -n1 || true)"

    [[ -z "$jar_url" ]] && return 1

    echo "${jar_url//&amp;/&}"
}

# ------------------------------------------------------------------------------
# Core: Download one plugin with fallback
# ------------------------------------------------------------------------------

download_plugin() {
    local engine="$1"
    local name="$2"
    local url="$3"
    local dest_dir="$4"
    local previous_dir="$5" # Managed dir for fallback
    local resolved_url="$url"
    local resolver=""

    local tag="[${engine}:${name}]"

    [[ -z "${url:-}" || "$url" == "null" ]] && return 0

    if [[ "$url" == https://builds.enginehub.org/job/* && "$url" != *.jar ]]; then
        resolver="EngineHub"
    elif [[ "$url" == *"/job/"* && "$url" != *.jar ]]; then
        resolver="Jenkins"
    elif [[ "$url" == https://github.com/*/releases* && "$url" != *.jar ]]; then
        resolver="GitHub"
    fi

    if [[ -n "$resolver" ]]; then
        echo -e "${PURPLE}[RESOLVE]${NC} ${tag} via ${resolver}..."

        case "$resolver" in
        EngineHub) resolved_url="$(resolve_enginehub "$url")" || resolved_url="" ;;
        Jenkins) resolved_url="$(resolve_jenkins "$engine" "$url")" || resolved_url="" ;;
        GitHub) resolved_url="$(resolve_github "$engine" "$url")" || resolved_url="" ;;
        esac

        if [[ -z "$resolved_url" ]]; then
            echo -e "${RED}[FAIL]${NC} ${tag} Failed to resolve URL" >&2

            # Fallback: Copy a previous version if available
            if [[ -d "$previous_dir" ]]; then
                local backup
                backup="$(find "$previous_dir" -maxdepth 1 -type f -iname "*${name}*.jar" | head -n1 || true)"
                if [[ -n "$backup" ]]; then
                    cp -p "$backup" "$dest_dir/"
                    echo -e "${GREEN}[RESTORE]${NC} ${tag} Preserved previous version"
                    return 0
                fi
            fi

            echo -e "${RED}[FAIL]${NC} ${tag} No fallback available" >&2

            return 1
        fi
    fi

    # Filename extraction
    local filename

    filename="$(basename "${resolved_url%%\?*}")"
    [[ "$filename" != *.jar ]] && filename="${name}.jar"

    local target="${dest_dir}/${filename}"
    local tmp="${target}.tmp.$$"

    echo -e "${BLUE}[DOWN]${NC} ${tag} Downloading ${filename}..."

    if curl -fsSL \
        --retry "${CURL_RETRY}" \
        --retry-delay "${CURL_RETRY_DELAY}" \
        --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
        -o "$tmp" \
        "$resolved_url"; then

        # Move to final location
        mv -f "$tmp" "$target"

        echo -e "${GREEN}[DONE]${NC} ${tag} Downloaded successfully: ${filename}"

        return 0
    fi

    rm -f "$tmp"
    echo -e "${YELLOW}[WARN]${NC} ${tag} Download failed. Trying fallback..." >&2

    # Fallback: Copy a previous version if available
    if [[ -d "$previous_dir" ]]; then
        local backup

        backup="$(find "$previous_dir" -maxdepth 1 -type f -iname "*${name}*.jar" | head -n1 || true)"

        if [[ -n "$backup" ]]; then
            cp -p "$backup" "$dest_dir/"
            echo -e "${GREEN}[RESTORE]${NC} ${tag} Preserved previous version"

            return 0
        fi
    fi

    echo -e "${RED}[FAIL]${NC} ${tag} No fallback available" >&2

    return 1
}

# ------------------------------------------------------------------------------
# Atomic directory swap: Managed.new -> Managed
# ------------------------------------------------------------------------------

atomic_swap_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    local backup="${dest_dir}.bak.$$"

    # Ensure dest parent exists
    mkdir -p "$(dirname "$dest_dir")"

    # If the existing directory exists, move it to backup
    if [[ -d "$dest_dir" ]]; then
        mv "$dest_dir" "$backup"
    fi

    # Attempt to move the new directory
    if ! mv "$src_dir" "$dest_dir"; then
        echo -e "${RED}[FATAL]${NC} Swap failed! Restoring backup..."

        # On failure, immediately attempt to restore backup
        if [[ -d "$backup" ]]; then
            mv "$backup" "$dest_dir"
        fi

        exit 1
    fi

    # On success, remove backup
    rm -rf "$backup" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

need_cmd jq
need_cmd curl
need_cmd realpath
need_cmd find

# Check config file
[[ -f "$CONFIG_FILE" ]] || die "Config file missing: $CONFIG_FILE"

mkdir -p "$PLUGIN_LIB_ROOT"

# Load configuration file
CONFIG="$(cat "$CONFIG_FILE")"

jq -e '.plugins and (.plugins | type=="object")' >/dev/null <<<"$CONFIG" ||
    die "Invalid config: expected '.plugins' object in ${CONFIG_FILE}"

echo -e "${BLUE}[INFO]${NC} Starting plugin updates..."

# Get engines safely (no subshell loop)
mapfile -t ENGINES < <(jq -r '.plugins | keys[]' <<<"$CONFIG")

for engine in "${ENGINES[@]}"; do
    echo "-----------------------------------------------------"
    echo -e "Processing Engine: ${GREEN}${engine}${NC}"
    echo "-----------------------------------------------------"

    ENGINE_ROOT="${PLUGIN_LIB_ROOT}/${engine}"
    TARGET_FINAL_DIR="${ENGINE_ROOT}/Managed"

    mkdir -p "$ENGINE_ROOT"

    # Temp managed dir inside engine root
    TEMP_DIR="$(mktemp -d -p "$ENGINE_ROOT" ".tmp_managed_XXXXXX")"
    TEMP_DIRS+=("$TEMP_DIR")

    # Collect plugin entries for this engine
    mapfile -t PLUGINS < <(jq -r ".plugins[\"$engine\"] | to_entries[] | \"\(.key)\t\(.value)\"" <<<"$CONFIG")

    declare -a pids=()

    for entry in "${PLUGINS[@]}"; do
        name="${entry%%$'\t'*}"
        url="${entry#*$'\t'}"
        download_plugin "$engine" "$name" "$url" "$TEMP_DIR" "$TARGET_FINAL_DIR" &
        pids+=("$!")
    done

    failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++)) || true
        fi
    done

    # If empty, skip swap
    if [[ -z "$(ls -A "$TEMP_DIR" 2>/dev/null || true)" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} No plugins downloaded/restored for '$engine'."
        rm -rf "$TEMP_DIR"
        continue
    fi

    # Abort if any plugin failed
    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}[ERROR]${NC} '$engine': ${failed} plugin(s) failed. Aborting swap to preserve existing state."
        rm -rf "$TEMP_DIR"
        continue
    fi

    # If empty skip swap
    if [[ -z "$(ls -A "$TEMP_DIR" 2>/dev/null || true)" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} No plugins downloaded/restored for '$engine'."
        rm -rf "$TEMP_DIR"
        continue
    fi

    # Atomic swap
    echo -e "${BLUE}[SWAP]${NC} Updating 'Managed' directory for '$engine'..."
    atomic_swap_dir "$TEMP_DIR" "$TARGET_FINAL_DIR"

    # `TEMP_DIR`` moved, remove it from cleanup list
    # (best-effort: rebuild TEMP_DIRS without that dir)
    if [[ ${#TEMP_DIRS[@]} -gt 0 ]]; then
        declare -a new_tmp=()
        for d in "${TEMP_DIRS[@]}"; do
            [[ "$d" == "$TARGET_FINAL_DIR" ]] && continue
            [[ "$d" == "$TEMP_DIR" ]] && continue
            new_tmp+=("$d")
        done
        TEMP_DIRS=("${new_tmp[@]}")
    fi

    if [[ $failed -gt 0 ]]; then
        echo -e "${YELLOW}[WARN]${NC} '$engine': ${failed} plugin(s) failed (fallback may have applied)."
    else
        echo -e "${GREEN}[OK]${NC} '$engine': all plugins updated."
    fi
done

echo "-----------------------------------------------------"
echo -e "${GREEN}[SUCCESS]${NC} All plugin updates complete."
