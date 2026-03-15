#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# defaults shema
# ------------------------------------------------------------------

SCHEDULE="47 2 * * *"
RSYNC_OPTIONS="-aHAX --delete"
TIMEZONE="Europe/Moscow"
TEST_MODE="false"

SOURCE_DEVICE=""
SOURCE_DIR="data"

DEST_DEVICE=""
DEST_DIR="backup"

POWER_ENABLED="false"
DISK_SWITCH=""

# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

load_config() {

    log_debug "load_config(): start"

    bashio::log "Loading config..."

    SCHEDULE=$(bashio::config 'schedule')
    RSYNC_OPTIONS=$(bashio::config 'rsync_options')
    TIMEZONE=$(bashio::config 'timezone')
    TEST_MODE=$(bashio::config 'test_mode')

    SOURCE_DEVICE=$(bashio::config 'storage.source_device')
    SOURCE_DIR=$(bashio::config 'storage.source_dir')

    DEST_DEVICE=$(bashio::config 'storage.destination_device')
    DEST_DIR=$(bashio::config 'storage.destination_dir')

    if bashio::config.true 'power.enabled'; then
        POWER_ENABLED=true
    else
        POWER_ENABLED=false
    fi

    DISK_SWITCH=$(bashio::config 'power.disk_switch')

    log_debug "Raw config values:"
    log_debug "  SCHEDULE=${SCHEDULE:-empty}"
    log_debug "  RSYNC_OPTIONS=${RSYNC_OPTIONS:-empty}"
    log_debug "  TIMEZONE=${TIMEZONE:-empty}"
    log_debug "  TEST_MODE=${TEST_MODE:-empty}"
    log_debug "  SOURCE_DEVICE=${SOURCE_DEVICE:-empty}"
    log_debug "  SOURCE_DIR=${SOURCE_DIR:-empty}"
    log_debug "  DEST_DEVICE=${DEST_DEVICE:-empty}"
    log_debug "  DEST_DIR=${DEST_DIR:-empty}"
    log_debug "  POWER_ENABLED=${POWER_ENABLED:-empty}"
    log_debug "  DISK_SWITCH=${DISK_SWITCH:-empty}"

    # ------------------------------------------------------------------
    # Information output
    # ------------------------------------------------------------------

    _print_value "Source device" "${SOURCE_DEVICE}"
    _print_value "Source dir" "${SOURCE_DIR}"
    _print_value "Destination device" "${DEST_DEVICE}"
    _print_value "Destination dir" "${DEST_DIR}"
    _print_value "Schedule" "${SCHEDULE}"
    _print_value "Rsync options" "${RSYNC_OPTIONS}"
    _print_value "Timezone" "${TIMEZONE}"

    if [ "${POWER_ENABLED}" = "true" ]; then
        power_value="\033[0;34menabled\033[0m"
    else
        power_value="\033[0;33mdisabled\033[0m"
    fi

    _print_value "Power control" "${power_value}"

    _print_value "Power switch" "${DISK_SWITCH}"

    # ------------------------------------------------------------------
    # Validating configuration
    # ------------------------------------------------------------------

    _validate_config || return 1

    # ------------------------------------------------------------------
    # Static paths
    # ------------------------------------------------------------------

    TARGET_ROOT="/mnt"

    SOURCE_PATH="${TARGET_ROOT}/${SOURCE_DEVICE}/${SOURCE_DIR}"
    DEST_PATH="${TARGET_ROOT}/${DEST_DEVICE}/${DEST_DIR}"

    log_debug "Derived paths:"
    log_debug "  SOURCE_PATH=${SOURCE_PATH}"
    log_debug "  DEST_PATH=${DEST_PATH}"

    log_debug "load_config(): completed"
}

# ------------------------------------------------------------------
# Pretty print helper
# ------------------------------------------------------------------

_print_value() {

    local label="$1"
    local value="$2"

    if [ -z "${value:-}" ]; then
        value="\033[0;33mnot set\033[0m"
    else
        value="\033[0;34m${value}\033[0m"
    fi

    bashio::log "$(printf '  %-18s : %s' "$label" "$value")"
}

# ------------------------------------------------------------------
# Validate format
# ------------------------------------------------------------------

_validate_config() {

    log_debug "_validate_config(): start"

    # normalize source dir
    SOURCE_DIR="${SOURCE_DIR#/}"
    SOURCE_DIR="$(echo "${SOURCE_DIR}" | sed 's://*:/:g')"

    # normalize dest dir
    DEST_DIR="${DEST_DIR#/}"
    DEST_DIR="$(echo "${DEST_DIR}" | sed 's://*:/:g')"

    # prevent path traversal
    if [[ "${SOURCE_DIR}" == *".."* ]] || [[ "${DEST_DIR}" == *".."* ]]; then
        bashio::log.red "Directory must not contain '..'"
        return 1
    fi

    # prevent identical source/destination
    if [ "$SOURCE_DEVICE" = "$DEST_DEVICE" ] && [ "$SOURCE_DIR" = "$DEST_DIR" ]; then
        bashio::log.red "Source and destination cannot be identical"
        return 1
    fi

    # Validate power configuration
    if [ "${POWER_ENABLED}" = "true" ]; then
        if [ -z "${DISK_SWITCH:-}" ]; then
            bashio::log.red "Power control is enabled but Power switch is not configured"
            return 1
        fi
    fi

    if [[ "$DISK_SWITCH" != switch.* ]]; then
        DISK_SWITCH="switch.${DISK_SWITCH}"
    fi
    
    log_debug "Final SOURCE_DIR=${SOURCE_DIR}"
    log_debug "Final DEST_DIR=${DEST_DIR}"

    log_debug "_validate_config(): completed"

    return 0
}
