#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

CONFIG_FILE="${ROOT_PATH}/config/update.json"
PLUGIN_ROOT="${ROOT_PATH}/libraries/plugins"

mkdir -p "$PLUGIN_ROOT"

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

# Resolve URLs and download them
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

# Resolve GitHub release URLs to direct download links
resolve_github() { # <github-release-url>
    local url="$1"
    local api_url repo tag asset_url
    repo=$(sed -E 's|https://github.com/([^/]+/[^/]+).*|\1|' <<<"$url")
    api_url="https://api.github.com/repos/$repo/releases/latest"

    # Call GitHub API
    local resp=$(curl -fsSL "$api_url") || return 1
    asset_url=$(jq -r '.assets[].browser_download_url' <<<"$resp" |
        grep -Ei '\.jar$' | grep -viE '(-sources|-javadoc)\.jar$' | head -n1)

    [[ -z "$asset_url" ]] && return 1
    printf '%s' "$asset_url"
}

# Resolve EngineHub URLs to direct download links
resolve_enginehub() { # <url>
    local url="$1"
    local final_url html jar_url

    # Follow redirect
    final_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "$url")
    [[ -z "$final_url" ]] && return 1

    # Fetch HTML
    html=$(curl -fsSL --retry 3 --retry-delay 5 "$final_url") || return 1

    # Grep .jar URL
    jar_url=$(grep -Eo 'https://ci\.enginehub\.org/repository/download/[^"]+\.jar\?[^"]+' <<<"$html" | head -n1)
    [[ -z "$jar_url" ]] && return 1

    # Decode &amp; to &
    jar_url=$(sed 's/&amp;/\&/g' <<<"$jar_url")

    printf '%s' "$jar_url"
}

update_plugins_for_engine() { # <engine>
    local engine="$1"
    local auto_dir="$PLUGIN_ROOT/$engine/auto"
    rm -r "$auto_dir" && mkdir -p "$auto_dir"
    echo "🧩 Plugin for $engine"

    while IFS=$'\t' read -r PLUGIN URL; do
        # Skip for manual://
        [[ "$URL" == manual://* ]] && continue

        # If URL is empty, skip
        [[ -z "$URL" ]] && {
            echo "  ⚠️ Skip $PLUGIN due to empty URL" >&2
            continue
        }

        # EngineHub special-case
        if [[ "$URL" == https://builds.enginehub.org/job/* && "$URL" != *.jar ]]; then
            echo "  🔍 Resolve EngineHub: $PLUGIN"
            URL=$(resolve_enginehub "$URL") || {
                echo "  ⚠️ Skip $PLUGIN due to EngineHub resolution failure" >&2
                continue
            }
        fi

        # Jenkins URL
        if [[ "$URL" == *"/job/"* && "$URL" != *.jar ]]; then
            echo "  🔍 Resolve Jenkins: $PLUGIN"
            URL=$(resolve_jenkins "$URL" "$engine") || {
                echo "  ⚠️ Skip $PLUGIN due to Jenkins resolution failure" >&2
                continue
            }
        fi

        # GitHub URL
        if [[ "$URL" == https://github.com/*/releases* && "$URL" != *.jar ]]; then
            echo "  🔍 Resolve GitHub Release: $PLUGIN"
            URL=$(resolve_github "$URL") || {
                echo "  ⚠️ Skip $PLUGIN due to GitHub resolution failure" >&2
                continue
            }
        fi

        # Get clean filename
        local JAR=$(basename "${URL%%\?*}")
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

echo "🎉 Getting plugins is complete."
