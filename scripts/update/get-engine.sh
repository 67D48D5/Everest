#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

mkdir -p "$ENGINE_DIR"

# Check if config file exists
[[ -f "$CONFIG_FILE" ]] || {
    echo "❌ update.json not found" >&2
    exit 1
}

# Check for required dependencies
for cmd in curl jq; do
    command -v "$cmd" >/dev/null || {
        echo "❌ Missing dependency: $cmd" >&2
        exit 1
    }
done

# Load the configuration file
CONFIG="$(cat "$CONFIG_FILE")"

# For engines, we will fetch the latest builds from PaperMC API
download_engine() { # <project> <version>
    local project="$1" version="$2"
    echo "🔄 Get $project with version $version"
    local api="https://api.papermc.io/v2/projects/$project/versions/$version/builds"
    local resp build jar url
    resp=$(curl -fsSL --retry 3 --retry-delay 5 "$api") || {
        echo "  ⚠️ API fetch failed for $project $version" >&2
        return
    }
    build=$(jq -r '.builds[-1].build' <<<"$resp")
    jar="${project}-${version}-${build}.jar"
    url="https://api.papermc.io/v2/projects/$project/versions/$version/builds/$build/downloads/$jar"
    echo "  ⬇️ Downloading $jar" && curl -fsSL --retry 3 --retry-delay 5 -o "$ENGINE_DIR/$jar" "$url" && echo "  ✅ Downloaded at $ENGINE_DIR/$jar"
}

clean_old() { # <dir> <prefix>
    find "$1" -maxdepth 1 -type f -name "$2-*.jar" -delete
}

jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG" |
    while IFS=$'\t' read -r ENGINE VERSION; do
        clean_old "$ENGINE_DIR" "$ENGINE"
        download_engine "$ENGINE" "$VERSION"
        echo
    done

echo "🎉 Getting engines is complete."
