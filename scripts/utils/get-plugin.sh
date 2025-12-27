#!/usr/bin/env bash
set -euo pipefail

# Configuration
# Setting up our paths relative to the script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Defining where our config and downloaded files are.
CONFIG_FILE="${ROOT_PATH}/config/update.json"
PLUGIN_ROOT="${ROOT_PATH}/libraries/plugins"

# Track temporary directories for cleanup
declare -a TEMP_DIRS=()

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ ${#TEMP_DIRS[@]} -gt 0 ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Cleaning up temporary directories..." >&2
        for temp_dir in "${TEMP_DIRS[@]}"; do
            if [[ -d "$temp_dir" ]]; then
                rm -rf "$temp_dir" || echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: Failed to clean up '$temp_dir'" >&2
            fi
        done
    fi
    exit "$exit_code"
}

# Set up trap for cleanup on exit
trap cleanup EXIT INT TERM

# Pre-flight Checks
# Let's get that plugin directory ready.
mkdir -p "$PLUGIN_ROOT"

# URL Resolver Functions
resolve_jenkins() { # <url> <engineKeyword>
    local url="$1" key="$2" api final
    api="${url%/}/lastSuccessfulBuild/api/json"
    local meta
    meta=$(curl -fsSL --retry 3 --retry-delay 5 "$api") || return 1
    local rel
    rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" |
        grep -Ei "${key}.*\.jar$" | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" |
        grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && return 1
    final="${url%/}/lastSuccessfulBuild/artifact/$rel"
    printf '%s' "$final"
}

resolve_github() { # <github-release-url>
    local url="$1" api_url repo asset_url resp
    repo=$(sed -E 's|https://github.com/([^/]+/[^/]+).*|\1|' <<<"$url")
    api_url="https://api.github.com/repos/$repo/releases/latest"
    resp=$(curl -fsSL "$api_url") || return 1
    asset_url=$(jq -r '.assets[].browser_download_url' <<<"$resp" |
        grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$asset_url" ]] && return 1
    printf '%s' "$asset_url"
}

resolve_enginehub() { # <url>
    local url="$1" final_url html jar_url
    final_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "$url")
    [[ -z "$final_url" ]] && return 1
    html=$(curl -fsSL --retry 3 --retry-delay 5 "$final_url") || return 1
    jar_url=$(grep -Eo 'https://ci\.enginehub\.org/repository/download/[^"]+\.jar\?[^"]+' <<<"$html" | head -n1)
    [[ -z "$jar_url" ]] && return 1
    jar_url="${jar_url//&amp;/&}"
    printf '%s' "$jar_url"
}

# Perform atomic directory swap
atomic_swap_directory() {
    local temp_dir="$1"
    local target_dir="$2"
    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Performing atomic directory swap..."
    rm -rf "$target_dir" || true
    mv "$temp_dir" "$target_dir"
}

# Remove a directory from the TEMP_DIRS tracking array
remove_from_temp_dirs() {
    local dir_to_remove="$1"
    local new_array=()
    for dir in "${TEMP_DIRS[@]}"; do
        [[ "$dir" != "$dir_to_remove" ]] && new_array+=("$dir")
    done
    TEMP_DIRS=("${new_array[@]}")
}

# Main Logic
process_plugin() {
    local engine="$1"
    local plugin_name="$2"
    local url="$3"
    local target_dir="$4"
    local resolved_url="$url" # Start with the original URL

    # Skip plugins marked for manual download
    if [[ "$url" == manual://* ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: '$plugin_name' is marked for manual download."
        return 0
    fi
    if [[ -z "$url" ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: '$plugin_name' has an empty URL. Skipping." >&2
        return 0
    fi

    # URL Resolution
    local resolution_type=""
    if [[ "$url" == https://builds.enginehub.org/job/* && "$url" != *.jar ]]; then
        resolution_type="EngineHub"
    elif [[ "$url" == *"/job/"* && "$url" != *.jar ]]; then
        resolution_type="Jenkins"
    elif [[ "$url" == https://github.com/*/releases* && "$url" != *.jar ]]; then
        resolution_type="GitHub"
    fi

    if [[ -n "$resolution_type" ]]; then
        echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Resolving $resolution_type URL for '$plugin_name'..."
        case "$resolution_type" in
        EngineHub) resolved_url=$(resolve_enginehub "$url") ;;
        Jenkins) resolved_url=$(resolve_jenkins "$url" "$engine") ;;
        GitHub) resolved_url=$(resolve_github "$url") ;;
        esac

        if [[ -z "$resolved_url" ]]; then
            echo "[$(date '+%H:%M:%S') ERROR] [get-plugin]: Failed to resolve URL for '$plugin_name'. Skipping." >&2
            return 1
        fi
    fi

    # Download
    local jar_name
    jar_name=$(basename "${resolved_url%%\?*}")
    if [[ "$jar_name" != *.jar ]]; then
        jar_name="${plugin_name}-${jar_name}.jar"
    fi

    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Downloading '$plugin_name' -> '$jar_name'..."
    if curl -fsSL --retry 3 --retry-delay 5 -o "$target_dir/$jar_name" "$resolved_url"; then
        echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Downloaded '$plugin_name' successfully."
    else
        echo "[$(date '+%H:%M:%S') ERROR] [get-plugin]: Failed to download '$plugin_name' from '$resolved_url'" >&2
        rm -f "$target_dir/$jar_name"
        return 1
    fi
}

# Execution
# Load the configuration once.
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$(date '+%H:%M:%S') ERROR] [get-plugin]: Configuration file not found: '$CONFIG_FILE'" >&2
    exit 1
fi

CONFIG="$(cat "$CONFIG_FILE")"
if [[ -z "$CONFIG" ]]; then
    echo "[$(date '+%H:%M:%S') ERROR] [get-plugin]: Configuration file is empty: '$CONFIG_FILE'" >&2
    exit 1
fi

# Loop through each engine (paper, velocity, etc.) sequentially.
jq -r '.plugins | keys[]' <<<"$CONFIG" | while read -r engine; do
    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Processing plugins for '$engine'..."

    # Define the parent directory for this engine's plugins.
    engine_plugin_dir="$PLUGIN_ROOT/$engine"
    # The final destination for the plugins.
    auto_dir="$engine_plugin_dir/Managed"

    # Reset arrays for this engine to prevent cross-contamination
    declare -a plugin_pids=()
    declare -a plugin_names=()

    # Ensure the parent directory exists first.
    mkdir -p "$engine_plugin_dir"

    # The SAFER Atomic Swap: Part 1
    # Use mktemp to create a secure, unique temporary directory.
    # This prevents race conditions where downloads from different engines
    # could write to the same place at the same time.
    temp_dir=$(mktemp -d -p "$engine_plugin_dir")
    TEMP_DIRS+=("$temp_dir")
    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Using temporary directory: $temp_dir"

    # Parallel Processing Loop
    # This process substitution `< <(...)` is the key. It prevents the
    # while loop from running in a subshell, so the 'wait' command
    # below is in the correct shell scope.
    while IFS=$'\t' read -r plugin_name url; do
        # The '&' runs each plugin process in the background!
        process_plugin "$engine" "$plugin_name" "$url" "$temp_dir" &
        plugin_pids+=($!)
        plugin_names+=("$plugin_name")
    done < <(jq -r ".plugins[\"$engine\"] | to_entries[] | \"\\(.key)\\t\\(.value)\"" <<<"$CONFIG")

    # This 'wait' is now in the main shell for this engine's loop.
    # It will correctly wait for ALL background 'process_plugin' jobs to finish
    # before the script proceeds to the atomic swap or the next engine.
    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Waiting for all '$engine' plugin downloads to complete..."

    # Track failed downloads and fall back to existing plugins when available
    shopt -s nullglob
    failed_downloads=0
    for idx in "${!plugin_pids[@]}"; do
        pid="${plugin_pids[$idx]}"
        plugin_name="${plugin_names[$idx]}"

        if ! wait "$pid"; then
            ((failed_downloads++))
            echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: Download failed for '$plugin_name'. Attempting fallback..." >&2
            # If a download fails, copy the existing plugin (if present) so the swap keeps it
            if [[ -d "$auto_dir" ]]; then
                existing_plugins=("$auto_dir"/${plugin_name}*.jar)
                if ((${#existing_plugins[@]})); then
                    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Falling back to existing '$plugin_name' from '$auto_dir'."
                    cp -p "${existing_plugins[@]}" "$temp_dir/" ||
                        echo "[$(date '+%H:%M:%S') ERROR] [get-plugin]: Failed to copy existing '$plugin_name'." >&2
                else
                    echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: No existing '$plugin_name' found in '$auto_dir' to fall back to." >&2
                fi
            else
                echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: Cannot fall back; '$auto_dir' does not exist." >&2
            fi
        fi
    done

    # If every download failed and nothing new was staged, keep the previous Managed contents intact
    staged_jars=("$temp_dir"/*.jar)
    if [[ $failed_downloads -eq ${#plugin_pids[@]} && ${#staged_jars[@]} -eq 0 && -d "$auto_dir" ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: All downloads failed for '$engine'; preserving existing plugins."
        cp -p "$auto_dir"/*.jar "$temp_dir/" 2>/dev/null || true
    fi
    shopt -u nullglob

    if [[ $failed_downloads -gt 0 ]]; then
        echo "[$(date '+%H:%M:%S') WARN] [get-plugin]: $failed_downloads plugin(s) failed to download for '$engine'." >&2
    fi

    # The Atomic Swap: Part 2
    # Once all downloads for this engine are complete, we swap the directories.
    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: All downloads for '$engine' complete. Swapping directories..."
    atomic_swap_directory "$temp_dir" "$auto_dir"

    # Remove from tracking since it's been successfully moved
    remove_from_temp_dirs "$temp_dir"

    echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: Finished processing plugins for '$engine'."
done

echo "[$(date '+%H:%M:%S') INFO] [get-plugin]: All plugin updates are complete."
