#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Static paths
# ------------------------------------------------------------------

BASE_DIR="/usr/local/backup_sync"
export BASE_DIR

# ------------------------------------------------------------------
# Simple pretty logger for addon
# User-friendly by default, debug via /config/debug.flag
# ------------------------------------------------------------------
DEBUG_FLAG="/config/debug.flag"

log_debug() {
    if [ -n "${DEBUG_FLAG:-}" ] && [ -f "${DEBUG_FLAG}" ]; then
        bashio::log.magenta "[DEBUG] $*"
    fi
}

_is_debug() {
    [ -f "${DEBUG_FLAG}" ]
}

log_debug "Script started"
log_debug "BASE_DIR=${BASE_DIR}"
log_debug "  DEBUG_FLAG=${DEBUG_FLAG}"

# ------------------------------------------------------------------
# Binaries
# ------------------------------------------------------------------

source "${BASE_DIR}/core/config.sh"
source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/detect.sh"
source "${BASE_DIR}/storage/mount.sh"

WATCHER_BIN="${BASE_DIR}/sync/watcher.py"
SCANNER_BIN="${BASE_DIR}/sync/scanner.py"
COPIER_BIN="${BASE_DIR}/sync/copier.sh"


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

emit() {
    log_debug "Emit called with args: $*"

    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || rc=$?

    if [ "${rc:-0}" -ne 0 ]; then
        log_debug "Emit failed rc=${rc}"
        fail_and_stop
    fi
}

# ------------------------------------------------------------------
# Exit & Error
# ------------------------------------------------------------------

fail_and_stop() {
    local caller="${FUNCNAME[1]}"
    log_debug "fail_and_stop triggered by ${caller}"

    local reason="${1:-fatal_err}"
    log_debug "Exiting with code \"${reason}\""


    if _is_debug; then
        bashio::log.yellow "Debug mode enabled — container will stay alive"
        log_debug "Entering infinite sleep (debug mode)"

        sleep infinity
    fi

    exit 1
}

# ---------------------------------------------------------
# runtime export
# ---------------------------------------------------------
write_runtime_env() {

    local RUNTIME_DIR="/run/backup_sync"
    local ENV_FILE="${RUNTIME_DIR}/runtime.env"
    local TMP_FILE="${ENV_FILE}.tmp"

    mkdir -p "${RUNTIME_DIR}"
    : > "${TMP_FILE}"

    printf 'BASE_DIR=%q\n' "$BASE_DIR" >> "$TMP_FILE"
    printf 'DEVICE=%q\n' "$DEVICE" >> "$TMP_FILE"
    printf 'SOURCE_DIR=%q\n' "/$SOURCE_DIR" >> "$TMP_FILE"
    printf 'TARGET_ROOT=%q\n' "$TARGET_ROOT" >> "$TMP_FILE"
    printf 'TARGET_DIR=%q\n' "$TARGET_DIR" >> "$TMP_FILE"
    printf 'QUEUE_FILE=%q\n' "$QUEUE_FILE" >> "$TMP_FILE"
    printf 'MAX_COPIES=%q\n' "$MAX_COPIES" >> "$TMP_FILE"
    printf 'SYNC_EXIST_START=%q\n' "$SYNC_EXIST_START" >> "$TMP_FILE"
    printf 'DEBUG_FLAG=%q\n' "$DEBUG_FLAG" >> "$TMP_FILE"
    printf 'TARGET_PATH=%q\n' "$TARGET_PATH" >> "$TMP_FILE"

    chmod 600 "$TMP_FILE"
    mv "$TMP_FILE" "$ENV_FILE"

    bashio::log.green "Runtime env write"
}

# ------------------------------------------------------------------
# Start
# ------------------------------------------------------------------
ADDON_VERSION="$(bashio::addon.version)"
ADDON_NAME=$(bashio::addon.name)

bashio::log "========================================"
bashio::log.green "=== ${ADDON_NAME} ==="
bashio::log.green "=== Version:  ${ADDON_VERSION} ==="
bashio::log.green "Starting at: $(date '+%Y-%m-%d %H:%M:%S')"
bashio::log "========================================"

emit service_state '{"reason":"addon_started"}'

# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

load_config || {
    bashio::log.red "Configuration load failed"
    log_debug "load_config returned error"
    fail_and_stop
}

log_debug "ENV DEVICE=$DEVICE TARGET_DIR=$TARGET_DIR SOURCE_DIR=$SOURCE_DIR"

write_runtime_env

# ------------------------------------------------------------------
# Storage validation
# ------------------------------------------------------------------

bashio::log.blue "=== Storage layer ==="
log_debug "Running check_storage"

if ! check_storage; then
    log_debug "check_storage failed — running detect_devices"
    detect_devices

    bashio::log.cyan "Please set parameter: device"
    bashio::log.yellow "Example: device: sdb1 | label | UUID"

    fail_and_stop
fi

log_debug "check_storage successful"

log_debug "Mounting USB"
mount_usb || fail_and_stop

log_debug "Checking target"
check_target || fail_and_stop

bashio::log.green "Mount and target checks completed"

# ------------------------------------------------------------------
# Flag barier
# ------------------------------------------------------------------
touch "/tmp/service.ready"

# ------------------------------------------------------------------
# Sync layer
# ------------------------------------------------------------------
bashio::log.blue " === Sync layer ==="

log_debug "Ready state emitted"

python3 "${WATCHER_BIN}" &
WATCHER_PID=$!
bashio::log.green "Starting file watcher..."

"${COPIER_BIN}" &
COPIER_PID=$!
bashio::log.green "Starting copy worker..."

if [ "${SYNC_EXIST_START}" = "true" ]; then
    python3 "${SCANNER_BIN}" || true
fi

bashio::log.green "System ready"
emit service_state '{"reason":"addon_ready"}'

wait "${COPIER_PID}"
