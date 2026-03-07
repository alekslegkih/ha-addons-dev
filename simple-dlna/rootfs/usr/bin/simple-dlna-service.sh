#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Static paths
# ------------------------------------------------------------------

BASE_DIR="/usr/local/simple-dlna"
export BASE_DIR

# ------------------------------------------------------------------
# Load runtime modules (теперь железо можно)
# ------------------------------------------------------------------

source "${BASE_DIR}/core/dlna_config.sh"
source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/mount.sh"
source "${BASE_DIR}/storage/detect.sh"

# ------------------------------------------------------------------
# Simple pretty logger for addon
# User-friendly by default, debug via /config/debug.flag
# ------------------------------------------------------------------

log_debug() {
    if [ -n "${DEBUG_FLAG:-}" ] && [ -f "${DEBUG_FLAG}" ]; then
        bashio::log.magenta "[DEBUG] $*"
    fi
}

log_debug "Script started"
log_debug "BASE_DIR=${BASE_DIR}"

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

emit() {
    log_debug "Emit called with args: $*"
    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || {
        log_debug "Emit failed (ignored)"
        true
    }
}

# ------------------------------------------------------------------
# Exit & Error
# ------------------------------------------------------------------

fail_and_stop() {
    local caller="${FUNCNAME[1]}"

    log_debug "fail_and_stop triggered by ${caller}"
    emit init_failed '{"reason":"fatal_err"}'

    if _is_debug; then
        bashio::log.yellow "Debug mode enabled — container will stay alive"
        log_debug "Entering infinite sleep (debug mode)"
        sleep infinity
    fi

    log_debug "Exiting with code 1"
    exit 1
}

# ------------------------------------------------------------------
# Load runtime ENV
# ------------------------------------------------------------------

log_debug "Checking runtime.env presence"

if [ ! -f /run/simple-dlna/runtime.env ]; then
    bashio::log.red "runtime.env not found"
    log_debug "runtime.env missing — exiting"
    exit 1
fi

log_debug "Loading runtime.env"

set -a
source /run/simple-dlna/runtime.env
set +a

log_debug "Runtime variables:"
log_debug " DEVICE=${DEVICE}"
log_debug " MEDIA_DIR=${MEDIA_DIR}"
log_debug " CONFIG_FILE=${CONFIG_FILE}"
log_debug " TARGET_ROOT=${TARGET_ROOT}"
log_debug " DLNA_DIR=${DLNA_DIR}"
log_debug " DEBUG_FLAG=${DEBUG_FLAG:-not_set}"

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
# DLNA configuration
# ------------------------------------------------------------------

log_debug "Initializing DLNA config"
init_dlna_config || fail_and_stop

bashio::log.green "Сonfiguration ready"
log_debug "DLNA config initialized"

# ------------------------------------------------------------------
# Flag barier 
# ------------------------------------------------------------------
touch "/run/simple-dlna/service.ready"

# ------------------------------------------------------------------
# Run 
# ------------------------------------------------------------------
bashio::log.blue "=== Starting ==="
emit service_state '{"reason":"addon_ready"}'
log_debug "Ready state emitted"

# ------------------------------------------------------------------
# Run minidlna
# ------------------------------------------------------------------
log_debug "Starting minidlnad with config ${CONFIG_FILE}"
exec minidlnad -f "$CONFIG_FILE" -S