#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# Load mount module (provides resolve_device function)
source "${BASE_DIR}/storage/mount.sh"


# Build mountpoint path for a given device
# Arguments:
#   $1 - device path (e.g., /dev/sdb1)
# Returns:
#   Full mountpoint path (e.g., /mnt/sdb1)
get_mountpoint() {

    local device="$1"
    local mount_name

    mount_name="$(basename "${device}")"

    printf '%s\n' "${TARGET_ROOT}/${mount_name}"
}


# Send event to Home Assistant via CLI helper
# Arguments:
#   $@ - event name and JSON payload
# Notes:
#   Errors are ignored (non-blocking behavior)
emit() {
    log_debug "Emit called with args: $*"
    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || {
        log_debug "Emit failed (ignored)"
        true
    }
}


# Validate device before using it for storage
# Ensures:
#   - device is provided
#   - device can be resolved
#   - device is not a protected system disk
#   - device has a filesystem
# Arguments:
#   $1 - device identifier (label, UUID, or path)
# Returns:
#   0 on success, non-zero on failure
check_device() {

    local device_input="$1"

    log_debug "check_device(): start"
    log_debug "Configured DEVICE=${device_input:-none}"

    # Ensure device is configured
    if [ -z "${device_input}" ]; then
        emit storage_failed '{"reason":"no_device_configured"}'
        return 1
    fi

    # Resolve device to actual path
    local device
    device="$(resolve_device "${device_input}")" || {
        emit storage_failed '{"reason":"device_not_found"}'
        return 1
    }

    log_debug "Resolved device=${device}"

    # Block known system disks to prevent data loss
    case "${device}" in
        /dev/sda*|/dev/mmcblk0*|/dev/nvme0n1*)
            emit storage_failed '{"reason":"system_device_blocked"}'
            return 1
            ;;
    esac

    # Detect filesystem type
    local fstype
    fstype="$(lsblk -no FSTYPE "${device}" 2>/dev/null || true)"

    log_debug "Detected filesystem=${fstype:-none}"

    # Reject devices without filesystem
    if [ -z "${fstype}" ]; then
        emit storage_failed '{"reason":"no_filesystem"}'
        return 1
    fi

    bashio::log.green "Device validation successful"
    return 0
}


# Validate source (read-only Nextcloud data)
# Ensures:
#   - device and directory are configured
#   - device is mounted
#   - directory exists
#   - directory is readable
# Uses:
#   SOURCE_DEVICE, SOURCE_DIR
# Returns:
#   0 on success, non-zero on failure
check_source() {

    log_debug "check_source(): start"

    # Ensure configuration is present
    if [ -z "${SOURCE_DEVICE}" ] || [ -z "${SOURCE_DIR}" ]; then
        return 1
    fi

    # Resolve source device
    local device
    device="$(resolve_device "${SOURCE_DEVICE}")" || {
        return 1
    }

    # Build source path
    local mountpoint
    mountpoint="$(get_mountpoint "${device}")"

    local source_path="${mountpoint}/${SOURCE_DIR}"

    log_debug "Source mountpoint=${mountpoint}"
    log_debug "Source path=${source_path}"

    # Ensure device is mounted
    if ! mountpoint -q "${mountpoint}"; then
        bashio::log.red "Source device not mounted"
        return 1
    fi

    # Ensure directory exists
    if [ ! -d "${source_path}" ]; then
        bashio::log.red "Source directory not found: ${source_path}"
        return 1
    fi

    # Verify read access
    if ! ls "${source_path}" >/dev/null 2>&1; then
        bashio::log.red "Source directory not readable"
        return 1
    fi

    return 0
}


# Validate destination (backup target)
# Ensures:
#   - device and directory are configured
#   - device is mounted
#   - directory exists (creates if missing)
#   - directory is writable
# Uses:
#   DEST_DEVICE, DEST_DIR
# Returns:
#   0 on success, non-zero on failure
check_destination() {

    log_debug "check_destination(): start"

    # Ensure configuration is present
    if [ -z "${DEST_DEVICE}" ] || [ -z "${DEST_DIR}" ]; then
        bashio::log.red "Destination configuration incomplete"
        return 1
    fi

    # Resolve destination device
    local device
    device="$(resolve_device "${DEST_DEVICE}")" || {
        bashio::log.red "Cannot resolve destination device"
        return 1
    }

    # Build destination path
    local mountpoint
    mountpoint="$(get_mountpoint "${device}")"

    local target_path="${mountpoint}/${DEST_DIR}"

    log_debug "Destination mountpoint=${mountpoint}"
    log_debug "Destination path=${target_path}"

    # Ensure device is mounted
    if ! mountpoint -q "${mountpoint}"; then
        bashio::log.red "Destination device not mounted"
        return 1
    fi

    # Create directory if missing
    if [ ! -d "${target_path}" ]; then

        bashio::log.yellow "Backup directory ${target_path} not found — creating"

        mkdir -p "${target_path}" || {
            bashio::log.red "Failed to create backup directory"
            return 1
        }

        log_debug "Backup directory created"
    fi

    # Verify write access
    local testfile="${target_path}/.write_test"

    if ! touch "${testfile}" 2>/dev/null; then
        bashio::log.red "Destination directory not writable"
        return 1
    fi

    rm -f "${testfile}"

    return 0
}