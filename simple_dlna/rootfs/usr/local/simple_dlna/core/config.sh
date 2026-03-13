#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Runtime defaults
# ------------------------------------------------------------------

DEVICE=""
MEDIA_DIR="dlna"
FRIENDLY_NAME="Simple DLNA"
LOG_LEVEL="info"


# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

load_config() {

    log_debug "load_config(): start"

    bashio::log "Loading config..."

    DEVICE=$(bashio::config 'device')
    MOUNT_POINT=$(bashio::config 'mount_point')
    MAX_COPIES=$(bashio::config 'max_copies')

    if bashio::config.true 'sync_exist_start'; then
        SYNC_EXIST_START=true
    fi

    log_debug "Raw config values:"
    log_debug "  DEVICE=${DEVICE:-empty}"
    log_debug "  MOUNT_POINT=${MOUNT_POINT:-empty}"
    log_debug "  MAX_COPIES=${MAX_COPIES:-empty}"
    log_debug "  SYNC_EXIST_START=${SYNC_EXIST_START:-empty}"

    # ------------------------------------------------------------------
    # Information output
    # ------------------------------------------------------------------

    if [ -z "${DEVICE:-}" ]; then
        usb_value="\033[0;33mnot set\033[0m"
    else
        usb_value="\033[0;34m${DEVICE}\033[0m"
    fi

    if [ -z "${MEDIA_DIR:-}" ]; then
        media_value="\033[0;33mnot set\033[0m"
    else
        media_value="\033[0;34m${MEDIA_DIR}\033[0m"
    fi

    if [ -z "${FRIENDLY_NAME:-}" ]; then
        name_value="\033[0;33mnot set\033[0m"
    else
        name_value="\033[0;34m${FRIENDLY_NAME}\033[0m"
    fi

    bashio::log "  Device     : ${usb_value}"
    bashio::log "  Media dir  : ${media_value}"
    bashio::log "  DLNA name  : ${name_value}"


    # ------------------------------------------------------------------
    # Validating target directory
    # ------------------------------------------------------------------

    _validate_config

    # ------------------------------------------------------------------
    # Static paths
    # ------------------------------------------------------------------

    CONFIG_DIR="/config"
    CONFIG_FILE="${CONFIG_DIR}/minidlna.conf"
    DB_DIR="${CONFIG_DIR}/db"
    TARGET_ROOT="/mnt"
    DLNA_DIR="${TARGET_ROOT}/${DEVICE}/${MEDIA_DIR}"
    DEBUG_FLAG="${CONFIG_DIR}/debug.flag"

    log_debug "Derived paths:"
    log_debug "  CONFIG_FILE=${CONFIG_FILE}"
    log_debug "  DB_DIR=${DB_DIR}"
    log_debug "  DLNA_DIR=${DLNA_DIR}"
    log_debug "  DEBUG_FLAG=${DEBUG_FLAG}"

    bashio::log.green "Configuration loaded"
    log_debug "load_config(): completed"
}

# ------------------------------------------------------------------
# Validate format
# ------------------------------------------------------------------

_validate_config() {

    log_debug "_validate_config(): start"

    # ----------------------------------------------------------
    # media_dir default
    # ----------------------------------------------------------

    if [ -z "${MEDIA_DIR}" ]; then
        MEDIA_DIR="dlna"
        bashio::log.yellow "Media dir not set — using default: ${MEDIA_DIR}"
        log_debug "MEDIA_DIR fallback applied"
    fi

    # ----------------------------------------------------------
    # Remove leading slashes
    # ----------------------------------------------------------

    if [[ "${MEDIA_DIR}" == /* ]]; then
        bashio::log.yellow "Media dir must not start with '/'. Normalizing."
        MEDIA_DIR="${MEDIA_DIR#/}"
        log_debug "Leading slash removed, MEDIA_DIR=${MEDIA_DIR}"
    fi

    # ----------------------------------------------------------
    # Prevent path traversal
    # ----------------------------------------------------------

    if [[ "${MEDIA_DIR}" == *".."* ]]; then
        bashio::log.red "Media dir must not contain '..'"
        return 1
    fi

    # ----------------------------------------------------------
    # Prevent empty after normalization
    # ----------------------------------------------------------

    if [ -z "${MEDIA_DIR}" ]; then
        MEDIA_DIR="dlna"
        log_debug "Media dir became empty after normalization — using default: ${MEDIA_DIR}"
    fi

    # ----------------------------------------------------------
    # friendly_name default
    # ----------------------------------------------------------

    if [ -z "${FRIENDLY_NAME}" ]; then
        FRIENDLY_NAME="Simple DLNA"
        bashio::log.yellow "FDLNA name not set — using default: ${FRIENDLY_NAME}"
        log_debug "FRIENDLY_NAME fallback applied"
    fi

    log_debug "Final MEDIA_DIR=${MEDIA_DIR}"
    log_debug "_validate_config(): completed"

    return 0
}
