#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"
SERVER_PATH="$(realpath "${ROOT_PATH}/servers")"
CACHE_DIR="$(realpath "${ROOT_PATH}/libraries/cache")"

# Link cache directory
# @TODO: Share common cache directory with all servers to avoid redundancy
