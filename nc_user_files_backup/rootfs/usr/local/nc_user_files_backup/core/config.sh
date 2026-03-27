#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# Default configuration values
# Used as fallback if options are not provided via Home Assistant config
SCHEDULE="47 2 * * *"
RSYNC_OPTIONS="-aHAX --delete"
TEST_MODE="false"

SOURCE_DEVICE=""
SOURCE_DIR=""

DEST_DEVICE=""
DEST_DIR=""

POWER_ENABLED="false"
DISK_SWITCH=""


# Load configuration from Home Assistant
# Reads all config values and prepares derived paths
# Also prints config summary and validates input
load_config() {

    log_debug "load_config(): start"

    bashio::log "Loading config..."

    # Read copy settings
    SCHEDULE=$(bashio::config 'schedule')
    RSYNC_OPTIONS=$(bashio::config 'rsync_options')

    # Read storage configuration
    SOURCE_DEVICE=$(bashio::config 'storage.source_devic')
    SOURCE_DIR=$(bashio::config 'storage.source_dir')
    DEST_DEVICE=$(bashio::config 'storage.destination_devic')
    DEST_DIR=$(bashio::config 'storage.destination_dir')

    # Read power control flag
    if bashio::config.true 'enabled'; then
        POWER_ENABLED=true
    else
        POWER_ENABLED=false
    fi
    DISK_SWITCH=$(bashio::config 'disk_switch')

    # Read test flag
    if bashio::config.true 'enabled'; then
        TEST_MODE=true
    else
        TEST_MODE=false
    fi
    TEST_MODE=$(bashio::config 'test_mode')

    if ! _validate_cron "$SCHEDULE"; then
        bashio::log.red "Invalid cron: '$SCHEDULE'"
        bashio::log.yellow "Using default from schema"
        return 1
    fi

    # Debug: raw config values
    log_debug "Raw config values:"
    log_debug "  SCHEDULE=${SCHEDULE:-empty}"
    log_debug "  RSYNC_OPTIONS=${RSYNC_OPTIONS:-empty}"
    log_debug "  TEST_MODE=${TEST_MODE:-empty}"
    log_debug "  SOURCE_DEVICE=${SOURCE_DEVICE:-empty}"
    log_debug "  SOURCE_DIR=${SOURCE_DIR:-empty}"
    log_debug "  DEST_DEVICE=${DEST_DEVICE:-empty}"
    log_debug "  DEST_DIR=${DEST_DIR:-empty}"
    log_debug "  POWER_ENABLED=${POWER_ENABLED:-empty}"
    log_debug "  DISK_SWITCH=${DISK_SWITCH:-empty}"

    # Print formatted configuration summary
    _print_value "Source device" "${SOURCE_DEVICE}"
    _print_value "Source dir" "${SOURCE_DIR}"
    _print_value "Destination device" "${DEST_DEVICE}"
    _print_value "Destination dir" "${DEST_DIR}"
    _print_value "Schedule" "${SCHEDULE}"
    _print_value "Rsync options" "${RSYNC_OPTIONS}"

    # Format test mode output with colors
    if [ "${TEST_MODE}" = "true" ]; then
        test_value="\033[0;34menabled\033[0m"
    else
        test_value="\033[0;33mdisabled\033[0m"
    fi
    _print_value "Test mode" "${test_value}"

    # Format power control output with colors
    if [ "${POWER_ENABLED}" = "true" ]; then
        power_value="\033[0;34menabled\033[0m"
    else
        power_value="\033[0;33mdisabled\033[0m"
    fi

    _print_value "Power control" "${power_value}"
    _print_value "Power switch" "${DISK_SWITCH}"

    # Validate configuration values
    _validate_config || return 1

    # Build static base paths
    TARGET_ROOT="/mnt"

    SOURCE_PATH="${TARGET_ROOT}/${SOURCE_DEVICE}/${SOURCE_DIR}"
    DEST_PATH="${TARGET_ROOT}/${DEST_DEVICE}/${DEST_DIR}"

    log_debug "Derived paths:"
    log_debug "  SOURCE_PATH=${SOURCE_PATH}"
    log_debug "  DEST_PATH=${DEST_PATH}"

    log_debug "load_config(): completed"
}


# Pretty-print key/value pair for logs
# Adds color and fallback for empty values
# Arguments:
#   $1 - label
#   $2 - value
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


# Validate and normalize configuration
# Ensures:
#   - directories are normalized
#   - no path traversal ("..")
#   - source and destination are not identical
#   - power configuration is valid
# Also normalizes DISK_SWITCH format
# Returns:
#   0 on success, non-zero on failure
_validate_config() {

    log_debug "_validate_config(): start"

    # Normalize source directory (remove leading slash and duplicate slashes)
    SOURCE_DIR="${SOURCE_DIR#/}"
    SOURCE_DIR="$(echo "${SOURCE_DIR}" | sed 's://*:/:g')"

    # Normalize destination directory
    DEST_DIR="${DEST_DIR#/}"
    DEST_DIR="$(echo "${DEST_DIR}" | sed 's://*:/:g')"

    # Prevent path traversal
    if [[ "${SOURCE_DIR}" == *".."* ]] || [[ "${DEST_DIR}" == *".."* ]]; then
        bashio::log.red "Directory must not contain '..'"
        return 1
    fi

    # Prevent identical source and destination
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

    # Ensure switch entity has proper prefix
    if [[ "$DISK_SWITCH" != switch.* ]]; then
        DISK_SWITCH="switch.${DISK_SWITCH}"
    fi

    log_debug "Final SOURCE_DIR=${SOURCE_DIR}"
    log_debug "Final DEST_DIR=${DEST_DIR}"

    log_debug "_validate_config(): completed"

    return 0
}


_validate_field() {
    local field="$1"
    local min="$2"
    local max="$3"

    [ "$field" = "*" ] && return 0

    IFS=',' read -ra parts <<< "$field"

    for part in "${parts[@]}"; do

        if [[ "$part" =~ ^\*/([0-9]+)$ ]]; then
            continue
        fi

        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}

            (( start >= min && end <= max && start <= end )) || return 1
            continue
        fi

        if [[ "$part" =~ ^[0-9]+$ ]]; then
            (( part >= min && part <= max )) || return 1
            continue
        fi

        return 1
    done

    return 0
}

_validate_cron() {
    local cron="$1"

    read -r f1 f2 f3 f4 f5 extra <<< "$cron"

    if [ -n "${extra:-}" ] || [ -z "${f5:-}" ]; then
        return 1
    fi

    _validate_field "$f1" 0 59 || return 1   # минуты
    _validate_field "$f2" 0 23 || return 1   # часы
    _validate_field "$f3" 1 31 || return 1   # день месяца
    _validate_field "$f4" 1 12 || return 1   # месяц
    _validate_field "$f5" 0 6  || return 1   # день недели

    return 0
}
