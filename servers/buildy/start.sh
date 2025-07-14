#!/usr/bin/env bash
set -euo pipefail

# Configuration
SERVER_NAME="buildy"
SERVER_ENGINE="paper"

# Java flags (See launcher for more details)
JAVA_FLAGS=(
  -Xms1024M
  -Xmx1024M
)

# Directory setup
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "$SCRIPT_DIR/../..")"

# Call generic launcher with extra flags
"$ROOT_PATH/scripts/bin/launcher" "$SERVER_NAME" "$SERVER_ENGINE" "${JAVA_FLAGS[@]}"
