#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Everest - Link Mounts (Static Asset Manager)
# ------------------------------------------------------------------------------
# Symlinks resources from libraries/common into server instances
# based on the "mounts" config in each server definition.
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
SERVERS_ROOT="${ROOT_PATH}/servers"

# shellcheck disable=SC2034
LOG_TAG="link-library"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/core/library"

# Pre-flight
for cmd in jq ln; do
    command -v "$cmd" &>/dev/null || {
        log_err "'$cmd' not found"
        exit 1
    }
done

[[ -f "$CONFIG_FILE" ]] || {
    log_err "Config missing: $CONFIG_FILE"
    exit 1
}
mkdir -p "$SERVERS_ROOT"

# Resolve branch
CONFIG="$(cat "$CONFIG_FILE")"
RESOLVED="$(resolve_branch "$CONFIG")"

# ------------------------------------------------------------------------------
# Core: Symlink a resource
# ------------------------------------------------------------------------------

link_resource() {
    local source_path="$1" dest_path="$2" name="$3" tag="$4"

    if [[ ! -e "$source_path" ]]; then
        log_warn "Source missing for ${tag}/${name}: $source_path"
        log_warn "Creating empty directory: $source_path"
        mkdir -p "$source_path"
    fi

    mkdir -p "$(dirname "$dest_path")"

    # Remove existing target (symlink, dir, or file)
    if [[ -L "$dest_path" ]]; then
        rm -f "$dest_path"
    elif [[ -d "$dest_path" ]]; then
        log_warn "Replacing directory with symlink: $dest_path"
        rm -rf "$dest_path"
    elif [[ -f "$dest_path" ]]; then
        log_warn "Replacing file with symlink: $dest_path"
        rm -f "$dest_path"
    fi

    ln -sfn "$source_path" "$dest_path"
    log_info "${tag}: ${name} → ${dest_path}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

# Iterate servers in resolved branch (keys with .engine field)
mapfile -t SERVERS < <(jq -r '
    to_entries[]
    | select(.value | type == "object" and has("engine"))
    | .key
' <<<"$RESOLVED")

for server in "${SERVERS[@]}"; do
    SERVER_DIR="${SERVERS_ROOT}/${server}"

    if [[ ! -d "$SERVER_DIR" ]]; then
        log_warn "Server directory missing: ${server}. Creating..."
        mkdir -p "$SERVER_DIR"
    fi

    # Check for mounts
    has_mounts="$(jq -r --arg s "$server" '.[$s].mounts // null | type' <<<"$RESOLVED")"

    if [[ "$has_mounts" != "object" ]]; then
        log_info "No mounts for ${server}. Skipping."
        continue
    fi

    log_info "Processing mounts: ${GREEN}${server}${NC}"

    while IFS=$'\t' read -r name src dest; do
        [[ -n "$name" && -n "$src" && -n "$dest" ]] || {
            log_warn "Invalid mount entry in ${server}: name=${name}"
            continue
        }
        link_resource "${COMMON_ROOT}/${src}" "${SERVER_DIR}/${dest}" "$name" "$server"
    done < <(jq -r --arg s "$server" '
        .[$s].mounts
        | to_entries[]
        | "\(.key)\t\(.value.src)\t\(.value.dest)"
    ' <<<"$RESOLVED")
done

log_info "Mount linking complete."
exit 0
