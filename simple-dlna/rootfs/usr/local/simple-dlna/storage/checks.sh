#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Device resolving
# ------------------------------------------------------------------

resolve_device() {
    local input="$1"
    local path
    local matches
    local count

    log_debug "resolve_device(): input=${input}"

    # ----------------------------------------------------------
    # 1. Direct device path (sdb2)
    # ----------------------------------------------------------

    path="/dev/${input}"
    log_debug "Checking direct path=${path}"

    if [ -b "${path}" ]; then
        log_debug "Resolved to ${path} (direct)"
        printf '%s\n' "${path}"
        return 0
    fi

    # ----------------------------------------------------------
    # 2. LABEL match (duplicate check, but keep by-label path)
    # ----------------------------------------------------------

    matches="$(blkid -t LABEL="${input}" -o device 2>/dev/null || true)"
    count="$(printf "%s\n" "${matches}" | sed '/^$/d' | wc -l)"

    if [ "${count}" -gt 1 ]; then
        bashio::log.red "Multiple devices found with LABEL=${input}"
        printf "%s\n" "${matches}" | while read -r dev; do
            bashio::log.red "  ${dev}"
        done
        bashio::log.red "Please use UUID instead."
        return 1
    fi

    if [ "${count}" -eq 1 ]; then
        path="/dev/disk/by-label/${input}"
        if [ -b "${path}" ]; then
            log_debug "Resolved via LABEL to ${path}"
            printf '%s\n' "${path}"
            return 0
        fi
    fi

    # ----------------------------------------------------------
    # 3. UUID match (duplicate check, keep by-uuid path)
    # ----------------------------------------------------------

    matches="$(blkid -t UUID="${input}" -o device 2>/dev/null || true)"
    count="$(printf "%s\n" "${matches}" | sed '/^$/d' | wc -l)"

    if [ "${count}" -gt 1 ]; then
        bashio::log.red "Multiple devices found with UUID=${input}"
        printf "%s\n" "${matches}" | while read -r dev; do
            bashio::log.red "  ${dev}"
        done
        return 1
    fi

    if [ "${count}" -eq 1 ]; then
        path="/dev/disk/by-uuid/${input}"
        if [ -b "${path}" ]; then
            log_debug "Resolved via UUID to ${path}"
            printf '%s\n' "${path}"
            return 0
        fi
    fi

    log_debug "resolve_device(): no matching block device found"
    return 1
}


# ------------------------------------------------------------------
# Storage validation
# ------------------------------------------------------------------

check_storage() {

    log_debug "check_storage(): start"
    log_debug "Configured DEVICE=${DEVICE:-none}"

    bashio::log.cyan "Connecting to configured device..."

    if [ -z "${DEVICE}" ]; then
        bashio::log.red "No device configured"
        emit storage_failed '{"reason":"no_device_configured"}'
        return 1
    fi

    local device
    device="$(resolve_device "${DEVICE}")" || {
        bashio::log.red "Device ${DEVICE} not found or not a block device"
        emit storage_failed '{"reason":"not_block_device"}'
        return 1
    }

    log_debug "Resolved device=${device}"

    case "${device}" in
        /dev/sda*|/dev/mmcblk0*|/dev/nvme0n1*)
            bashio::log.red "Refusing to use system device: ${device}"
            emit storage_failed '{"reason":"system_device_blocked"}'
            return 1
            ;;
    esac

    log_debug "Detecting filesystem via lsblk"

    local fstype
    fstype="$(lsblk -no FSTYPE "${device}" 2>/dev/null || true)"

    log_debug "Detected fstype=${fstype:-none}"

    if [ -z "${fstype}" ]; then
        bashio::log.red "Filesystem not detected on ${device}"
        emit storage_failed '{"reason":"no_filesystem"}'
        return 1
    fi

    bashio::log.green "Connection successful."
    log_debug "check_storage(): success"
    return 0
}


# ------------------------------------------------------------------
# Target validation
# ------------------------------------------------------------------

check_target() {

    log_debug "check_target(): start"

    # ----------------------------------------------------------
    # Safety check (should never fail after validation)
    # ----------------------------------------------------------

    if [ -z "${MEDIA_DIR}" ]; then
        bashio::log.red "MEDIA_DIR is empty (validation failure)"
        return 1
    fi

    local device
    device="$(resolve_device "${DEVICE}")" || {
        bashio::log.red "Cannot resolve device in check_target"
        return 1
    }

    log_debug "Resolved device=${device}"

    local mount_name
    mount_name="$(basename "${device}")"

    local target="/${TARGET_ROOT}/${mount_name}"
    local media_path="${target}/${MEDIA_DIR}"

    log_debug "Mount target=${target}"
    log_debug "Media path=${media_path}"

    # ----------------------------------------------------------
    # Verify mountpoint
    # ----------------------------------------------------------

    if ! mountpoint -q "${target}"; then
        bashio::log.red "Target ${target} is not a mountpoint"
        return 1
    fi

    log_debug "Mountpoint verified"

    # ----------------------------------------------------------
    # Ensure media directory exists
    # ----------------------------------------------------------

    if [ ! -d "${media_path}" ]; then
        bashio::log "Media directory ${media_path} not found — creating"

        mkdir -p "${media_path}" || {
            bashio::log.red "Failed to create media directory"
            return 1
        }

        log_debug "Media directory created"
    fi

    # ----------------------------------------------------------
    # Write test
    # ----------------------------------------------------------

    local testfile="${media_path}/.write_test"
    log_debug "Write test file=${testfile}"

    if ! touch "${testfile}" 2>/dev/null; then
        bashio::log.red "Media directory not writable"
        return 1
    fi

    rm -f "${testfile}"
    log_debug "Write test passed"

    bashio::log.green "Storage layer ready"
    log_debug "check_target(): success"

    return 0
}