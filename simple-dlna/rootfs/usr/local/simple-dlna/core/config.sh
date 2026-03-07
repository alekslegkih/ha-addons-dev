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

load_config() {

    log_debug "load_config(): start"

    OPTION_FILE="/data/options.json"
    log_debug "Options file=${OPTION_FILE}"

    if [ ! -f "${OPTION_FILE}" ]; then
        log_error "Config file ${OPTION_FILE} not found"
    fi

    bashio::log "Loading config..."

    DEVICE="$(jq -r '.device // empty' "${OPTION_FILE}")"
    MEDIA_DIR="$(jq -r '.media_dir // empty' "${OPTION_FILE}")"
    FRIENDLY_NAME="$(jq -r '.friendly_name // empty' "${OPTION_FILE}")"
    LOG_LEVEL="$(jq -r '.log_level // empty' "${OPTION_FILE}")"

    log_debug "Raw config values:"
    log_debug "  DEVICE=${DEVICE:-empty}"
    log_debug "  MEDIA_DIR=${MEDIA_DIR:-empty}"
    log_debug "  FRIENDLY_NAME=${FRIENDLY_NAME:-empty}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL:-empty}"


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