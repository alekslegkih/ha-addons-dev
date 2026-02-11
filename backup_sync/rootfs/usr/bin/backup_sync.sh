#!/command/with-contenv bashio
# shellcheck shell=bash

set -uo pipefail

BASE_DIR="/usr/local/backup_sync"
DEBUG_FLAG="/config/debug.flag"

source "${BASE_DIR}/core/logger.sh"
source "${BASE_DIR}/core/config.sh"
source "${BASE_DIR}/core/notify.sh"

source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/mount.sh"


WATCHER_BIN="${BASE_DIR}/sync/watcher.py"
SCANNER_BIN="${BASE_DIR}/sync/scanner.py"
COPIER_BIN="${BASE_DIR}/sync/copier.sh"

# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------

_is_debug() {
  [ -f "${DEBUG_FLAG}" ]
}

fail_and_stop() {
  log_error "$1"

  if _is_debug; then
    log_warn "Debug mode enabled — staying alive for investigation"
  else
    exit 1
  fi
}

# ---------------------------------------------------------
load_config      || fail_and_stop "Config load failed"

export MOUNT_POINT MAX_COPIES USB_DEVICE SYNC_EXIST_START NOTIFY_SERVICE

log_section "Processing the storage layer"

check_storage    || fail_and_stop "Storage connection failed"
mount_usb        || fail_and_stop "Mount sysytem failed"
check_target     || fail_and_stop "Target checks failed"

# -----------------------------------------------------------

log_section "Sync layer starting"

python3 "${WATCHER_BIN}" &
WATCHER_PID=$!
log_ok "Watcher started"

"${COPIER_BIN}" &
COPIER_PID=$!
log_ok "Copier started"

if [ "${SYNC_EXIST_START}" = "true" ]; then
  echo
  python3 "${SCANNER_BIN}" || true
fi

echo
log_ok "System ready"

wait "${COPIER_PID}"
