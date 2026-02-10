#!/command/with-contenv bashio
# shellcheck shell=bash

set -uo pipefail 

BASE_DIR="/usr/local/backup_sync"
DEBUG_FLAG="/config/debug.flag"

source "${BASE_DIR}/core/logger.sh"
source "${BASE_DIR}/core/config.sh"

source "${BASE_DIR}/storage/detect.sh"
source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/mount.sh"


COPIER_BIN="${BASE_DIR}/sync/copier.sh"
SCANNER_BIN="${BASE_DIR}/sync/scanner.py"

# ---------------------------------------------------------
# Supervisor helpers
# ---------------------------------------------------------

_is_debug() {
  [ -f "${DEBUG_FLAG}" ]
}

fail_or_sleep() {
  log_error "$1"

  if _is_debug; then
    log_warn "Debug mode enabled — staying alive for investigation"
  else
    exit 1
  fi
}

# ---------------------------------------------------------
# Hard-layer bring-up
# ---------------------------------------------------------

log_section "Processing the storage layer"

load_config      || fail_and_stop "Config load failed"

export MOUNT_POINT MAX_COPIES NOTIFY_SERVICE

detect_devices   || fail_and_stop "Device detection failed"
check_storage    || fail_and_stop "Storage checks failed"
mount_usb        || fail_and_stop "Mount failed"
check_target     || fail_and_stop "Target checks failed"

log_section "Storage layer ready"



# ---------------------------------------------------------
# Sync-layer bring-up (НОВОЕ)
# ---------------------------------------------------------

log_section "Starting copier"

"${COPIER_BIN}" &
COPIER_PID=$!

log_section "Running initial scan"

python3 "${SCANNER_BIN}" || true

log_section "System running"

wait "${COPIER_PID}"