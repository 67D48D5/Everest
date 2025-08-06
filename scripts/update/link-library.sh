#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

CONFIG_FILE="${ROOT_PATH}/config/server.json"
COMMON_ROOT="${ROOT_PATH}/libraries/common"
SERVERS_ROOT="${ROOT_PATH}/servers"

# Check if config file exists
[[ -f "$CONFIG_FILE" ]] || {
    echo "❌ server.json not found" >&2
    exit 1
}

# Check for required dependencies
for cmd in jq realpath; do
    command -v "$cmd" >/dev/null || {
        echo "❌ Missing dependency: $cmd" >&2
        exit 1
    }
done

# Load the configuration file
CONFIG="$(cat "$CONFIG_FILE")"

# Iterate over servers in the config
jq -r '.servers | keys[]' <<<"$CONFIG" | while read -r SERVER; do
    ENGINE=$(jq -r ".servers[\"$SERVER\"].engine" <<<"$CONFIG")
    SERVER_DIR="${SERVERS_ROOT}/${SERVER}"

    echo "🔗 Processing server: ${SERVER} (engine: ${ENGINE})"

    # 1. Link 'cache' directory (for Paper servers only)
    # Source: ROOT_PATH/libraries/common/cache
    # Destination: SERVERS_ROOT/${SERVER}/cache
    if [[ "$ENGINE" == "paper" ]]; then
        SOURCE_CACHE_DIR="${COMMON_ROOT}/cache"
        DEST_CACHE_DIR="${SERVER_DIR}/cache"

        # Ensure source directory exists
        [[ -d "$SOURCE_CACHE_DIR" ]] || mkdir -p "$SOURCE_CACHE_DIR"

        if [[ -L "$DEST_CACHE_DIR" ]]; then
            echo "   - 'cache' is already a symlink. Removing old link."
            rm "$DEST_CACHE_DIR"
        elif [[ -d "$DEST_CACHE_DIR" ]]; then
            echo "   - 'cache' is a directory. Removing existing directory."
            rm -rf "$DEST_CACHE_DIR"
        fi
        echo "   - Linking 'cache' from ${SOURCE_CACHE_DIR} to ${DEST_CACHE_DIR}"
        ln -sfn "$SOURCE_CACHE_DIR" "$DEST_CACHE_DIR"
    fi

    # 2. Link 'libraries' directory (for Paper servers only)
    # Source: ROOT_PATH/libraries/common/libraries
    # Destination: SERVERS_ROOT/${SERVER}/libraries
    if [[ "$ENGINE" == "paper" ]]; then
        SOURCE_LIBS_DIR="${COMMON_ROOT}/libraries"
        DEST_LIBS_DIR="${SERVER_DIR}/libraries"

        # Ensure source directory exists
        [[ -d "$SOURCE_LIBS_DIR" ]] || mkdir -p "$SOURCE_LIBS_DIR"

        if [[ -L "$DEST_LIBS_DIR" ]]; then
            echo "   - 'libraries' is already a symlink. Removing old link."
            rm "$DEST_LIBS_DIR"
        elif [[ -d "$DEST_LIBS_DIR" ]]; then
            echo "   - 'libraries' is a directory. Removing existing directory."
            rm -rf "$DEST_LIBS_DIR"
        fi
        echo "   - Linking 'libraries' from ${SOURCE_LIBS_DIR} to ${DEST_LIBS_DIR}"
        ln -sfn "$SOURCE_LIBS_DIR" "$DEST_LIBS_DIR"
    fi

    # 3. Link 'versions' directory (for Paper servers only)
    # Source: ROOT_PATH/libraries/common/versions
    # Destination: SERVERS_ROOT/${SERVER}/versions
    if [[ "$ENGINE" == "paper" ]]; then
        SOURCE_VERSIONS_DIR="${COMMON_ROOT}/versions"
        DEST_VERSIONS_DIR="${SERVER_DIR}/versions"

        # Ensure source directory exists
        [[ -d "$SOURCE_VERSIONS_DIR" ]] || mkdir -p "$SOURCE_VERSIONS_DIR"

        if [[ -L "$DEST_VERSIONS_DIR" ]]; then
            echo "   - 'versions' is already a symlink. Removing old link."
            rm "$DEST_VERSIONS_DIR"
        elif [[ -d "$DEST_VERSIONS_DIR" ]]; then
            echo "   - 'versions' is a directory. Removing existing directory."
            rm -rf "$DEST_VERSIONS_DIR"
        fi
        echo "   - Linking 'versions' from ${SOURCE_VERSIONS_DIR} to ${DEST_VERSIONS_DIR}"
        ln -sfn "$SOURCE_VERSIONS_DIR" "$DEST_VERSIONS_DIR"
    fi

    # 4. Link 'LuckPerms/libs'
    # Source: ROOT_PATH/libraries/common/plugins/LuckPerms/libs
    # Destination: SERVERS_ROOT/${SERVER}/plugins/LuckPerms/libs
    SOURCE_LUCKPERMS_DIR="${COMMON_ROOT}/plugins/LuckPerms/libs"
    DEST_LUCKPERMS_DIR="${SERVER_DIR}/plugins/LuckPerms/libs"
    if [[ "$ENGINE" == "velocity" ]]; then
        DEST_LUCKPERMS_DIR="${SERVER_DIR}/plugins/luckperms/libs"
    fi

    # Ensure source directory exists
    [[ -d "$SOURCE_LUCKPERMS_DIR" ]] || mkdir -p "$SOURCE_LUCKPERMS_DIR"

    if [[ -L "$DEST_LUCKPERMS_DIR" ]]; then
        echo "   - 'LuckPerms/libs' is already a symlink. Removing old link."
        rm "$DEST_LUCKPERMS_DIR"
    elif [[ -d "$DEST_LUCKPERMS_DIR" ]]; then
        echo "   - 'LuckPerms/libs' is a directory. Removing existing directory."
        rm -rf "$DEST_LUCKPERMS_DIR"
    fi
    echo "   - Linking 'LuckPerms/libs' from ${SOURCE_LUCKPERMS_DIR} to ${DEST_LUCKPERMS_DIR}"
    ln -sfn "$SOURCE_LUCKPERMS_DIR" "$DEST_LUCKPERMS_DIR"

    echo
done

echo "✅ Common resource linking complete."
