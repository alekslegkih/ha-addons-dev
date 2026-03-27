#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# fallback если нет bashio (с цветами, без префиксов)
if ! command -v bashio::log >/dev/null 2>&1; then

    _c_reset="\033[0m"
    _c_green="\033[32m"
    _c_red="\033[31m"
    _c_yellow="\033[33m"
    _c_blue="\033[34m"

    bashio::log() {
        echo -e "$*"
    }

    bashio::log.green() {
        echo -e "${_c_green}$*${_c_reset}"
    }

    bashio::log.red() {
        echo -e "${_c_red}$*${_c_reset}"
    }

    bashio::log.yellow() {
        echo -e "${_c_yellow}$*${_c_reset}"
    }

    bashio::log.blue() {
        echo -e "${_c_blue}$*${_c_reset}"
    }

fi

DIR_ADDON="nc_user_files_backup"
BASE_DIR="/usr/local/${DIR_ADDON}"
RUNTIME_DIR="/run/${DIR_ADDON}"
RUNTIME_ENV="${RUNTIME_DIR}/runtime.env"

# Check if debug mode is enabled via debug flag file
_is_debug() {
    [ -n "${DEBUG_FLAG:-}" ] && [ -f "${DEBUG_FLAG}" ]
}

# Log debug messages with magenta color when debug mode is enabled
log_debug() {
    if _is_debug; then
        bashio::log.magenta "[DEBUG] $*"
    fi
}

# Load runtime environment and required scripts
if [ ! -f "${RUNTIME_ENV}" ]; then
    bashio::log.red "Runtime environment file not found: ${RUNTIME_ENV}"
    exit 1
fi

source "${RUNTIME_ENV}"
log_debug "Loading runtime environment"

# Load required modules for power management, storage operations, and sync
log_debug "Loading modules"
source "${BASE_DIR}/power/on_off.sh"
source "${BASE_DIR}/storage/mount.sh"
source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/detect.sh"

# Helpers
emit() {
    log_debug "Emit called with args: $*"
    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || {
        log_debug "Emit failed (ignored)"
        true
    }
}

power_on_and_wait_disk() {

    # Power on the backup device
    if [ "${POWER_ENABLED}" = "true" ]; then
        bashio::log "Powering on backup device..."

        power_on || {
            bashio::log.red "Backup disk power-on failed (${DISK_SWITCH})"
            return 1
        }

        bashio::log "Preparing backup disk, please wait a few seconds..."

        # Wait for the disk to appear only if the power was turned on
        if ! wait_disk 25; then
            if [ -n "${DEST_DEVICE:-}" ]; then
                bashio::log.red "Backup disk not found: ${DEST_DEVICE}"
            else
                bashio::log.red "Destination device is not set"
            fi

            bashio::log.yellow "Make sure the disk is connected and powered on."
            detect_devices
            bashio::log.yellow "  You can use:"
            bashio::log.yellow "    - device name (sdb1)"
            bashio::log.yellow "    - filesystem label"
            bashio::log.yellow "    - UUID"

            return 1
        fi
    fi

    return 0
}


mount_and_check_destination() {

    # Mount destination device
    bashio::log.green "Backup disk found: ${DEST_DEVICE}"
    bashio::log "Mounting destination storage..."

    if ! mount_destination; then
        bashio::log.red "Failed to mount destination device: ${DEST_DEVICE}"
        return 1
    fi

    # Validate that backup directory exists on destination
    if ! check_destination; then

        bashio::log.yellow "  Check parameters:"
        bashio::log.yellow "    Destination device: ${DEST_DEVICE}"
        bashio::log.yellow "    Destination dir: ${DEST_DIR}    | Example: Backups"
        bashio::log.red "Backup directory validation failed"

        umount_destination || true

        return 1
    fi

    bashio::log.green "Destination storage ready"

    return 0
}

umount_and_poweroff() {

    # Unmount destination storage
    bashio::log "Unmounting destination storage..."

    if ! umount_destination; then
        bashio::log.red "Unmount storage failed"
        return 1
    fi

    bashio::log.green "Storage successfully unmounted"

    # Power off the backup device
    if [ "${POWER_ENABLED}" = "true" ]; then
        bashio::log "Powering off backup device..."

        power_off || {
            bashio::log.red "Backup disk power-off failed (${DISK_SWITCH})"
            return 1
        }
    fi

    return 0
}
