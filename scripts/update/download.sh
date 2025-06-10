#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"
PLUGIN_ROOT="${ROOT_PATH}/libraries/plugins"

mkdir -p "$ENGINE_DIR" "$PLUGIN_ROOT"

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

CONFIG="$(cat "$CONFIG_FILE")"

# For engines, we will fetch the latest builds from PaperMC API
clean_old() { # <dir> <prefix>
    find "$1" -maxdepth 1 -type f -name "$2-*.jar" -delete
}

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

jq -r '.engines | to_entries[] | "\(.key)\t\(.value.version)"' <<<"$CONFIG" |
    while IFS=$'\t' read -r ENGINE VERSION; do
        clean_old "$ENGINE_DIR" "$ENGINE"
        download_engine "$ENGINE" "$VERSION"
        echo
    done

# For plugins, we will resolve URLs and download them
resolve_jenkins() { # <url> <engineKeyword>
    local url="$1" key="$2" api final
    api="${url%/}/lastSuccessfulBuild/api/json"
    local meta=$(curl -fsSL --retry 3 --retry-delay 5 "$api") || return 1
    local rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" |
        grep -Ei "${key}.*\.jar$" | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && rel=$(jq -r '.artifacts[].relativePath' <<<"$meta" |
        grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)
    [[ -z "$rel" ]] && return 1
    final="${url%/}/lastSuccessfulBuild/artifact/$rel"
    printf '%s' "$final"
}

update_plugins_for_engine() { # <engine>
    local engine="$1"
    local auto_dir="$PLUGIN_ROOT/$engine/autoupdate"
    mkdir -p "$auto_dir"
    echo "🧩 $engine"

    while IFS=$'\t' read -r PLUGIN URL; do
        # Skip for manual://
        [[ "$URL" == manual://* ]] && continue

        # Jenkins URL 해결
        if [[ "$URL" == *"/job/"* && "$URL" != *.jar ]]; then
            echo "  🔍 Resolve Jenkins: $PLUGIN"
            URL=$(resolve_jenkins "$URL" "$engine") || {
                echo "  ⚠️ Skip $PLUGIN due to Jenkins resolution failure" >&2
                continue
            }
        fi

        local JAR=$(basename "$URL")
        [[ "$JAR" != *.jar ]] && JAR="${PLUGIN}-${JAR}.jar"

        echo "  ⬇️ $PLUGIN → $JAR"
        if curl -fsSL --retry 3 --retry-delay 5 -o "$auto_dir/$JAR" "$URL"; then
            echo "  ✅ Downloaded at $auto_dir/$JAR"
        else
            echo "  ❌ Fail to download $PLUGIN from $URL"
        fi
    done < <(jq -r ".plugins[\"$engine\"] | to_entries[] | \"\\(.key)\\t\\(.value)\"" <<<"$CONFIG")

    echo
}

jq -r '.plugins | keys[]' <<<"$CONFIG" | while read -r ENG; do update_plugins_for_engine "$ENG"; done

echo "🎉 Updates complete."
