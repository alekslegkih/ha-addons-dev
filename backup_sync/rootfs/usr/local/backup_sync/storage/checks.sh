#!/command/with-contenv bashio
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
    # 1. Direct device path
    # ----------------------------------------------------------

    path="/dev/${input}"
    log_debug "Checking direct path=${path}"

    if [ -b "${path}" ]; then
        log_debug "Resolved to ${path} (direct)"
        printf '%s\n' "${path}"
        return 0
    fi

    # ----------------------------------------------------------
    # 2. LABEL match
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
    # 3. UUID match
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
# System device detection
# ------------------------------------------------------------------

is_system_device() {

    local device="$1"
    local data_partition
    local data_disk
    local device_disk

    log_debug "is_system_device(): start"
    log_debug "Input device=${device}"

    # ----------------------------------------------------------
    # Find Home Assistant data partition
    # ----------------------------------------------------------

    data_partition="/dev/disk/by-label/hassos-data"

    log_debug "Expected Home Assistant data symlink=${data_partition}"

    if [ ! -e "${data_partition}" ]; then
        log_debug "Home Assistant data symlink does not exist"
        return 2
    fi

    if [ ! -b "${data_partition}" ]; then
        log_debug "Home Assistant data path exists but is not a block device"
        log_debug "Path=${data_partition}"
        return 2
    fi

    log_debug "Home Assistant data symlink found"

    data_partition="$(readlink -f "${data_partition}" 2>/dev/null || true)"

    if [ -z "${data_partition}" ]; then
        log_debug "Failed to resolve Home Assistant data symlink"
        return 2
    fi

    log_debug "Resolved Home Assistant data partition=${data_partition}"

    # ----------------------------------------------------------
    # Resolve Home Assistant physical disk
    # ----------------------------------------------------------

    data_disk="$(lsblk -no PKNAME "${data_partition}" 2>/dev/null || true)"

    log_debug "Home Assistant data PKNAME=${data_disk:-none}"

    if [ -z "${data_disk}" ]; then
        log_debug "Unable to determine Home Assistant data disk"
        return 2
    fi

    log_debug "Home Assistant physical disk=${data_disk}"

    # ----------------------------------------------------------
    # Resolve selected physical disk
    # ----------------------------------------------------------

    device_disk="$(lsblk -no PKNAME "${device}" 2>/dev/null || true)"

    log_debug "Selected device PKNAME=${device_disk:-none}"

    # If selected device is a whole disk, PKNAME is empty.
    if [ -z "${device_disk}" ]; then

        log_debug "PKNAME empty, assuming selected device may be a whole disk"

        device_disk="$(basename "$(readlink -f "${device}" 2>/dev/null || true)")"

        log_debug "Resolved selected device basename=${device_disk:-none}"
    fi

    if [ -z "${device_disk}" ]; then
        log_debug "Unable to determine selected device disk"
        return 2
    fi

    log_debug "Home Assistant data disk=${data_disk}"
    log_debug "Selected device disk=${device_disk}"

    # ----------------------------------------------------------
    # Compare physical disks
    # ----------------------------------------------------------

    if [ "${device_disk}" = "${data_disk}" ]; then
        log_debug "Selected device belongs to Home Assistant data disk"
        log_debug "is_system_device(): result=SYSTEM"
        return 0
    fi

    log_debug "Selected device does not belong to Home Assistant data disk"
    log_debug "is_system_device(): result=NOT_SYSTEM"

    return 1
}


# ------------------------------------------------------------------
# Storage validation
# ------------------------------------------------------------------

check_storage() {

    local device
    local system_check
    local fstype

    log_debug "check_storage(): start"
    log_debug "Configured DEVICE=${DEVICE:-none}"

    bashio::log.cyan "Connecting to configured device..."

    if [ -z "${DEVICE}" ]; then
        bashio::log.red "No device configured"

        emit storage_failed \
            '{"reason":"device_error", "error":"no_device_configured"}'

        return 1
    fi

    device="$(resolve_device "${DEVICE}")" || {
        bashio::log.red \
            "Device ${DEVICE} not found or not a block device"

        emit storage_failed \
            '{"reason":"device_error", "error":"not_block_device"}'

        return 1
    }

    log_debug "Resolved device=${device}"

    # ----------------------------------------------------------
    # Check whether device belongs to Home Assistant system disk
    # ----------------------------------------------------------

    log_debug "Running system device check for ${device}"

    is_system_device "${device}"
    system_check=$?

    log_debug "is_system_device() returned code=${system_check}"

    case "${system_check}" in

        0)
            log_debug \
                "Selected device is part of Home Assistant data disk"

            bashio::log.red \
                "Home Assistant system disk cannot be used: ${device}"

            bashio::log.yellow \
                "Please select another disk for storage"

            emit storage_failed \
                '{"reason":"device_error", "error":"system_device_blocked"}'

            return 1
            ;;

        1)
            log_debug "Selected device passed system disk check"
            ;;

        2)
            log_debug "System disk detection failed"

            bashio::log.red \
                "Unable to determine Home Assistant data disk"

            emit storage_failed \
                '{"reason":"device_error", "error":"system_device_check_failed"}'

            return 1
            ;;

        *)
            log_debug \
                "Unexpected return code from is_system_device(): ${system_check}"

            bashio::log.red \
                "Unable to determine Home Assistant data disk"

            emit storage_failed \
                '{"reason":"device_error", "error":"system_device_check_failed"}'

            return 1
            ;;
    esac

    # ----------------------------------------------------------
    # Detect filesystem
    # ----------------------------------------------------------

    log_debug "Detecting filesystem via lsblk"

    fstype="$(lsblk -no FSTYPE "${device}" 2>/dev/null || true)"

    log_debug "Detected fstype=${fstype:-none}"

    if [ -z "${fstype}" ]; then
        bashio::log.red \
            "Filesystem not detected on ${device}"

        emit storage_failed \
            '{"reason":"device_error", "error":"no_filesystem"}'

        log_debug "check_storage(): failed reason=no_filesystem"
        return 1
    fi

    log_debug "Filesystem validation passed"
    log_debug "Device=${device}"
    log_debug "Filesystem=${fstype}"

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
    # Safety check
    # ----------------------------------------------------------

    if [ -z "${TARGET_DIR}" ]; then
        bashio::log.red \
            "TARGET_DIR is empty (validation failure)"
        return 1
    fi

    local device
    device="$(resolve_device "${DEVICE}")" || {
        bashio::log.red \
            "Cannot resolve device in check_target"
        return 1
    }

    log_debug "Resolved device=${device}"

    local mount_name
    mount_name="$(basename "${device}")"

    local target="${TARGET_ROOT}/${mount_name}"
    local target_path="${target}/${TARGET_DIR}"

    log_debug "Mount target=${target}"
    log_debug "Target path=${target_path}"

    # ----------------------------------------------------------
    # Verify mountpoint
    # ----------------------------------------------------------

    if ! mountpoint -q "${target}"; then
        bashio::log.red \
            "Target ${target} is not a mountpoint"
        return 1
    fi

    log_debug "Mountpoint verified"

    # ----------------------------------------------------------
    # Ensure target directory exists
    # ----------------------------------------------------------

    if [ ! -d "${target_path}" ]; then
        bashio::log \
            "Target directory ${target_path} not found — creating"

        mkdir -p "${target_path}" || {
            bashio::log.red \
                "Failed to create target directory"
            return 1
        }

        log_debug "Target directory created"
    fi

    # ----------------------------------------------------------
    # Write test
    # ----------------------------------------------------------

    local testfile="${target_path}/.write_test"

    log_debug "Write test file=${testfile}"

    if ! touch "${testfile}" 2>/dev/null; then
        bashio::log.red \
            "Target directory not writable"
        return 1
    fi

    rm -f "${testfile}"

    log_debug "Write test passed"

    bashio::log.green "Storage layer ready"
    log_debug "check_target(): success"

    return 0
}
