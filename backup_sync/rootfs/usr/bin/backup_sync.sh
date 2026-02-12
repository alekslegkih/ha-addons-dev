#!/command/with-contenv bashio
# shellcheck shell=bash

set -uo pipefail

# =========================================================
# Bootstrap only
# =========================================================

BASE_DIR="/usr/local/backup_sync"
export BASE_DIR

source "${BASE_DIR}/core/logger.sh"
source "${BASE_DIR}/core/config.sh"

source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/mount.sh"


# =========================================================
# emit helper
# =========================================================

emit() {
  python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || true
}


# =========================================================
# debug & exit
# =========================================================

fail_and_stop() {
  log_error "$1"

  if _is_debug; then
    log_warn "Debug mode enabled — staying alive for investigation"
  else
    exit 1
  fi
}


# =========================================================
# Load config 
# =========================================================

load_config || fail_and_stop "Config load failed"


# =========================================================
# Binaries
# =========================================================

WATCHER_BIN="${BASE_DIR}/sync/watcher.py"
SCANNER_BIN="${BASE_DIR}/sync/scanner.py"
COPIER_BIN="${BASE_DIR}/sync/copier.sh"


# =========================================================
# Storage layer
# =========================================================

log_section "Processing the storage layer"

check_storage || fail_and_stop "Storage connection failed"
mount_usb     || fail_and_stop "Mount system failed"
check_target  || fail_and_stop "Target checks failed"


# =========================================================
# Sync layer
# =========================================================

log_section "Sync layer starting"

python3 "${WATCHER_BIN}" &
WATCHER_PID=$!
log_ok "Watcher started"

"${COPIER_BIN}" &
COPIER_PID=$!
log_ok "Copier started"

if [ "${SYNC_EXIST_START}" = "true" ]; then
  python3 "${SCANNER_BIN}" || true
fi

log_ok "System ready"

wait "${COPIER_PID}"
