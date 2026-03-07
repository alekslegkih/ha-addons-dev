#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Static paths
# ------------------------------------------------------------------

BASE_DIR="/usr/local/simple-dlna"
export BASE_DIR

# ------------------------------------------------------------------
# Start 
# ------------------------------------------------------------------

bashio::log "========================================"
bashio::log.green "=== Simple DLNA addon starting ==="
bashio::log.green "Starting at: $(date '+%Y-%m-%d %H:%M:%S')"
bashio::log "========================================"

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
# Load modules
# ------------------------------------------------------------------

log_debug "Loading modules..."

source "${BASE_DIR}/core/config.sh"

log_debug "Modules ${BASE_DIR} loaded"

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
# Runtime ENV writer
# ------------------------------------------------------------------

write_runtime_env() {

    local RUNTIME_DIR="/run/simple-dlna"
    local ENV_FILE="${RUNTIME_DIR}/runtime.env"
    local TMP_FILE="${ENV_FILE}.tmp"

    log_debug "Preparing runtime env directory: ${RUNTIME_DIR}"
    mkdir -p "${RUNTIME_DIR}"

    log_debug "Writing runtime env to temp file: ${TMP_FILE}"
    : > "${TMP_FILE}"

    printf 'DEVICE=%q\n' "$DEVICE" >> "$TMP_FILE"
    printf 'MEDIA_DIR=%q\n' "$MEDIA_DIR" >> "$TMP_FILE"
    printf 'FRIENDLY_NAME=%q\n' "$FRIENDLY_NAME" >> "$TMP_FILE"
    printf 'LOG_LEVEL=%q\n' "$LOG_LEVEL" >> "$TMP_FILE"
    printf 'CONFIG_DIR=%q\n' "$CONFIG_DIR" >> "$TMP_FILE"
    printf 'CONFIG_FILE=%q\n' "$CONFIG_FILE" >> "$TMP_FILE"
    printf 'DB_DIR=%q\n' "$DB_DIR" >> "$TMP_FILE"
    printf 'TARGET_ROOT=%q\n' "$TARGET_ROOT" >> "$TMP_FILE"
    printf 'DLNA_DIR=%q\n' "$DLNA_DIR" >> "$TMP_FILE"
    printf 'DEBUG_FLAG=%q\n' "$DEBUG_FLAG" >> "$TMP_FILE"

    chmod 600 "$TMP_FILE"
    mv "$TMP_FILE" "$ENV_FILE"

    log_debug "Runtime env written to ${ENV_FILE}"
}

# ------------------------------------------------------------------
# Main (configuration phase only)
# ------------------------------------------------------------------

log_debug "Emitting addon_started event"
emit service_state '{"reason":"addon_started"}'

bashio::log.blue "=== Configuration ==="
log_debug "Starting configuration phase"

load_config || {
    bashio::log.red "Configuration load failed"
    log_debug "load_config returned error"
    exit 1
}

log_debug "Configuration loaded successfully"
log_debug "DEVICE=${DEVICE}"
log_debug "MEDIA_DIR=${MEDIA_DIR}"
log_debug "FRIENDLY_NAME=${FRIENDLY_NAME}"
log_debug "LOG_LEVEL=${LOG_LEVEL}"
log_debug "CONFIG_DIR=${CONFIG_DIR}"
log_debug "CONFIG_FILE=${CONFIG_FILE}"
log_debug "DB_DIR=${DB_DIR}"
log_debug "TARGET_ROOT=${TARGET_ROOT}"
log_debug "DLNA_DIR=${DLNA_DIR}"
log_debug "DEBUG_FLAG=${DEBUG_FLAG:-not_set}"

write_runtime_env

log_debug "Configuration phase completed"
log_debug "Script exiting successfully"

exit 0