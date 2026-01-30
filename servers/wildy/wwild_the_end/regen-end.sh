#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Regen - Ender World Regeneration (Safe)
# ------------------------------------------------------------------------------
# Default: delete DIM1 only (The End dimension data), keep level.dat/world meta.
# Options: --full (delete whole world_the_end folder), --backup, --dry-run
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Setting up our paths relative to the script's location.
TARGET_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

# Logging helper functions
log_info() { echo -e "[$(date '+%H:%M:%S') ${GREEN}INFO${NC}] [regen-end]: $1"; }
log_warn() { echo -e "[$(date '+%H:%M:%S') ${YELLOW}WARN${NC}] [regen-end]: $1"; }
log_err() { echo -e "[$(date '+%H:%M:%S') ${RED}ERROR${NC}] [regen-end]: $1" >&2; }

usage() {
    cat <<'EOF'
Usage: regen-end.sh [options]

Options:
  --dim1-only        Delete DIM1 only (default, safest)
  --full             Delete entire target dir contents (dangerous; prefer deleting folder itself externally)
  --backup           Create a timestamped backup before deletion
  --backup-dir DIR   Backup base directory (default: ./backups)
  --dry-run          Show what would be deleted, do nothing
  --port N           If set, block when something listens on this port (optional)
  -h, --help         Show help

Notes:
- Run with the server STOPPED.
- For typical End reset: deleting DIM1 is enough.
EOF
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

# Default options
MODE="dim1"
DO_BACKUP="0"
BACKUP_BASE="${TARGET_DIR}/backups"
DRY_RUN="0"
CHECK_PORT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dim1-only)
        MODE="dim1"
        shift
        ;;
    --full)
        MODE="full"
        shift
        ;;
    --backup)
        DO_BACKUP="1"
        shift
        ;;
    --backup-dir)
        BACKUP_BASE="$2"
        shift 2
        ;;
    --dry-run)
        DRY_RUN="1"
        shift
        ;;
    --port)
        CHECK_PORT="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        log_err "Unknown option: $1"
        usage
        exit 2
        ;;
    esac
done

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

# Optional port check (environment dependent)
if [[ -n "${CHECK_PORT}" ]]; then
    if lsof -i :"${CHECK_PORT}" >/dev/null 2>&1; then
        log_err "Something is listening on port ${CHECK_PORT}. Stop the server first."
        exit 1
    fi
fi

# Basic world sanity check
if [[ ! -f "${TARGET_DIR}/level.dat" ]]; then
    log_err "No level.dat found in ${TARGET_DIR}. This doesn't look like a world directory."
    exit 1
fi

# If session.lock exists, warn (not always reliable, but useful)
if [[ -f "${TARGET_DIR}/session.lock" ]]; then
    log_warn "session.lock exists. Server might still be running or crashed. Make sure it's fully stopped."
fi

# ------------------------------------------------------------------------------
# Backup
# ------------------------------------------------------------------------------

timestamp="$(date '+%Y%m%d_%H%M%S')"
backup_path="${BACKUP_BASE}/end_backup_${timestamp}.tar.gz"

do_tar_backup() {
    mkdir -p "${BACKUP_BASE}"
    log_info "Creating backup: ${backup_path}"
    # Back up only what we might delete
    if [[ "${MODE}" == "dim1" ]]; then
        tar -czf "${backup_path}" -C "${TARGET_DIR}" "DIM1" 2>/dev/null || {
            log_warn "DIM1 not found; backup will include only metadata files."
            tar -czf "${backup_path}" -C "${TARGET_DIR}" "level.dat" "level.dat_old" "session.lock" 2>/dev/null || true
        }
    else
        tar -czf "${backup_path}" -C "${TARGET_DIR}" . 2>/dev/null || true
    fi
}

if [[ "${DO_BACKUP}" == "1" ]]; then
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[dry-run] Would create backup at: ${backup_path}"
    else
        do_tar_backup
    fi
fi

# ------------------------------------------------------------------------------
# Deletion Plan
# ------------------------------------------------------------------------------

declare -a targets=()

if [[ "${MODE}" == "dim1" ]]; then
    # Safest: reset only The End dimension data
    targets=("DIM1")
else
    # Dangerous mode: delete common world files (keeping the folder itself)
    # NOTE: still avoids blindly nuking everything unless you really want it.
    targets=("DIM1" "session.lock" "level.dat_old")
    # Intentionally NOT deleting level.dat by default even in full mode
fi

log_info "Starting End world regeneration (mode=${MODE}) in: ${TARGET_DIR}"

for t in "${targets[@]}"; do
    p="${TARGET_DIR}/${t}"
    if [[ -e "${p}" ]]; then
        if [[ "${DRY_RUN}" == "1" ]]; then
            log_info "[dry-run] Would delete: ${t}"
        else
            rm -rf "${p}"
            log_info "Deleted: ${t}"
        fi
    else
        log_warn "Not found, skipping: ${t}"
    fi
done

log_info "Done. Restart server to regenerate The End."
if [[ "${DO_BACKUP}" == "1" ]]; then
    log_info "Backup: ${backup_path}"
fi
