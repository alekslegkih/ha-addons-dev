#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


mount_usb() {

    log_debug "mount_usb(): start"
    log_debug "Requested DEVICE=${DEVICE}"
    log_debug "TARGET_ROOT=${TARGET_ROOT}"

    local device
    device="$(resolve_device "${DEVICE}")" || {
        bashio::log.red "Device ${DEVICE} not found"
        log_debug "resolve_device() failed"
        emit storage_failed '{"reason":"device_not_found"}'
        return 1
    }

    log_debug "Resolved device=${device}"

    if [ ! -b "${device}" ]; then
        bashio::log.red "Resolved path is not a block device: ${device}"
        log_debug "ls -l ${device}: $(ls -l "${device}" 2>/dev/null || echo 'not accessible')"
        emit storage_failed '{"reason":"device_error", "error":"not_block_device"}'
        return 1
    fi

    local mount_name
    mount_name="$(basename "${device}")"
    local target="${TARGET_ROOT}/${mount_name}"

    log_debug "Mount name=${mount_name}"
    log_debug "Mount target=${target}"

    if ! mkdir -p "${target}"; then
        bashio::log.red "Cannot create ${target}"
        log_debug "mkdir failed with exit code=$?"
        emit storage_failed '{"reason":"device_error", "error":"mkdir_failed"}'
        return 1
    fi

    log_debug "Directory ensured: ${target}"

    if mountpoint -q "${target}"; then
        bashio::log.red "Target ${target} is already a real mountpoint"
        log_debug "Existing mount: $(findmnt "${target}" || echo 'unknown')"
        emit storage_failed '{"reason":"device_error", "error":"already_mounted"}'
        return 1
    else
        log_debug "Target is not an active mountpoint"
    fi

    # ----------------------------------------------------------
    # Check if already mounted somewhere else (bind scenario)
    # ----------------------------------------------------------

    local src_mount
    src_mount="$(findmnt -n -o TARGET --source "${device}" 2>/dev/null || true)"

    if [ -n "${src_mount}" ]; then
        log_debug "Device already mounted at ${src_mount}"
        log_debug "Attempting bind mount ${src_mount} -> ${target}"

        if mount --bind "${src_mount}" "${target}"; then
            bashio::log.green "Bind mount successful"
            log_debug "Bind mount exit code=$?"
            emit storage_mounted '{"reason":"bind"}'
            return 0
        else
            bashio::log.red "Bind mount failed"
            log_debug "Bind mount exit code=$?"
            emit storage_failed '{"reason":"device_error", "error":"bind_failed"}'
            return 1
        fi
    else
        log_debug "Device is not mounted elsewhere (direct mount required)"
    fi

    # ----------------------------------------------------------
    # Detect filesystem
    # ----------------------------------------------------------

    log_debug "Detecting filesystem type via blkid"

    local fstype
    fstype="$(blkid -o value -s TYPE "${device}" 2>/dev/null || true)"

    log_debug "blkid exit code=$?"
    log_debug "Detected filesystem='${fstype:-none}'"

    if [ -z "${fstype}" ]; then
        bashio::log.red "Filesystem type not detected"
        log_debug "blkid output empty for ${device}"
        emit storage_failed '{"reason":"device_error", "error":"unknown_fs"}'
        return 1
    fi

    # ----------------------------------------------------------
    # Direct mount with fs-specific handling
    # ----------------------------------------------------------

    log_debug "Preparing mount strategy for fs=${fstype}"

    # ----------------------------------------------------------
    # Special handling for NTFS (kernel -> ntfs-3g fallback)
    # ----------------------------------------------------------

    if [ "${fstype}" = "ntfs" ]; then
        log_debug "Filesystem is NTFS -> trying kernel ntfs first"

        if mount -t ntfs -o rw,uid=0,gid=0,umask=022 "$device" "$target"; then
            log_debug "Mounted using kernel ntfs driver"
        else
            local first_exit=$?
            log_debug "Kernel ntfs mount failed with code=${first_exit}"
            log_debug "Trying fallback to ntfs-3g"

            if mount -t ntfs-3g -o rw,uid=0,gid=0,umask=022 "$device" "$target"; then
                log_debug "Mounted using ntfs-3g fallback"
            else
                local second_exit=$?
                log_debug "ntfs-3g mount failed with code=${second_exit}"

                bashio::log.red "Direct mount failed (ntfs + ntfs-3g)"
                emit storage_failed "{"reason":"device_error","fs=ntfs"}"
                return 1
            fi
        fi

    # ----------------------------------------------------------
    # All other filesystems
    # ----------------------------------------------------------

    else
        local mount_args=()

        case "${fstype}" in
            exfat)
                log_debug "Filesystem is exFAT"
                mount_args=(-t exfat -o rw,uid=0,gid=0,umask=022 "$device" "$target" )
                ;;
            vfat|fat|fat32)
                log_debug "Filesystem is FAT"
                mount_args=(-t vfat -o rw,uid=0,gid=0,umask=022 "$device" "$target" )
                ;;
            *)
                log_debug "Filesystem is ${fstype} -> generic mount"
                mount_args=(-t "$fstype" "$device" "$target" )
                ;;
        esac

        log_debug "Executing mount with args: ${mount_args[*]}"

        if ! mount "${mount_args[@]}"; then
            local exit_code=$?
            bashio::log.red "Direct mount failed"
            log_debug "Mount failed with exit code=${exit_code}"

            log_debug "Kernel dmesg (last 10 lines):"
            log_debug "$(dmesg | tail -n 10)"

            emit "{\"reason\":\"device_error\", \"error\":\"fs=${fstype}\"}"
            return 1
        fi
    fi

    # ----------------------------------------------------------
    # Final verification
    # ----------------------------------------------------------

    if mountpoint -q "${target}"; then
        log_debug "Final verification successful: ${target} is a mountpoint"
        log_debug "findmnt result:"
        log_debug "$(findmnt "${target}")"

        # emit storage_mounted "{\"reason\":\"direct\",\"fs\":\"${fstype}\"}"
        return 0
    else
        bashio::log.red "Mount command succeeded but mountpoint check failed"
        log_debug "findmnt output:"
        log_debug "$(findmnt "${target}" || echo 'not found')"
        emit "{\"reason\":\"device_error\", \"error\":\"fs=${fstype}\"}"

        return 1
    fi
}
