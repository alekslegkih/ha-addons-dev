#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# === Event Emission Helper ===
# Send events to Home Assistant for monitoring and notifications

emit() {
    log_debug "Emit called with args: $*"
    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || {
        log_debug "Emit failed (ignored)"
        true  # Prevent script failure if emission fails
    }
}

# === Disk Detection Helper ===
# Wait for a new disk to appear and return its device name
# Used for detecting backup drives that are powered on after script starts
# Arguments:
#   $1 - timeout in seconds (default: 20)
# Returns: device name (e.g., "sda") on success, non-zero exit code on timeout
wait_disk() {
    local timeout=${1:-20}
    local start=$(date +%s)
    
    # Get list of currently connected disks at script start
    # Searches for SCSI/SATA (sd*), NVMe, and eMMC devices
    local initial=$(ls /dev/sd[b-z] /dev/nvme[0-9]n[0-9] /dev/mmcblk[0-9] 2>/dev/null)
    log_debug "Initial disks: $(echo $initial | sed 's|/dev/||g' | tr '\n' ' ')"
    
    # Poll for new disks until timeout is reached
    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        local current=$(ls /dev/sd[b-z] /dev/nvme[0-9]n[0-9] /dev/mmcblk[0-9] 2>/dev/null)
        
        # Check each currently connected disk
        for disk in $current; do
            if ! echo "$initial" | grep -qxF "$disk"; then
                log_debug "New disk detected: ${disk#/dev/}"
                sleep 3  # Give the disk time to fully initialize
                log_debug "${disk#/dev/}" 
                return 0
            fi
        done
        
        sleep 1  # Wait before next poll
    done
    
    log_debug "Timeout reached: no new disks found"
    return 1
}

# === Device Resolution ===
# Convert device identifier (path, label, or UUID) to actual device path
# Arguments:
#   $1 - device identifier (e.g., "sdb1", "LABEL=backup", "UUID=1234")
# Returns: device path on success, non-zero exit code on failure
resolve_device() {
    local input="$1"
    local path
    local matches
    local count

    log_debug "resolve_device(): input=${input}"

    # 1. Try as direct device path (e.g., /dev/sdb1)
    path="/dev/${input}"
    if [ -b "${path}" ]; then
        printf '%s\n' "${path}"
        return 0
    fi

    # 2. Try as filesystem LABEL
    matches="$(blkid -t LABEL="${input}" -o device 2>/dev/null || true)"
    count="$(printf "%s\n" "${matches}" | sed '/^$/d' | wc -l)"

    if [ "${count}" -gt 1 ]; then
        log_debug "Multiple LABEL matches for ${input}"
        return 1
    fi

    if [ "${count}" -eq 1 ]; then
        path="/dev/disk/by-label/${input}"
        [ -b "${path}" ] && printf '%s\n' "${path}" && return 0
    fi

    # 3. Try as filesystem UUID
    matches="$(blkid -t UUID="${input}" -o device 2>/dev/null || true)"
    count="$(printf "%s\n" "${matches}" | sed '/^$/d' | wc -l)"

    if [ "${count}" -gt 1 ]; then
        log_debug "Multiple UUID matches for ${input}"
        return 1
    fi

    if [ "${count}" -eq 1 ]; then
        path="/dev/disk/by-uuid/${input}"
        [ -b "${path}" ] && printf '%s\n' "${path}" && return 0
    fi

    log_debug "resolve_device(): not found"
    return 1
}

# === Core Mount Engine ===
# Mount a device with specified mode, handling different filesystem types
# Arguments:
#   $1 - device identifier (passed to resolve_device)
#   $2 - mount mode ("ro" for read-only, "rw" for read-write)
# Returns: 0 on success, 1 on failure
mount_core() {
    local device_input="$1"
    local mode="$2"

    log_debug "mount_core(): start"
    log_debug "Requested DEVICE=${device_input}"
    log_debug "Mount mode=${mode}"

    # Resolve device identifier to actual device path
    local device
    device="$(resolve_device "${device_input}")" || {
        log_debug "resolve_device failed"
        emit storage_failed '{"reason":"device_not_found"}'
        return 1
    }

    # Verify it's a valid block device
    [ -b "${device}" ] || {
        log_debug "Not a block device: ${device}"
        emit storage_failed '{"reason":"not_block_device"}'
        return 1
    }

    # Create mount point directory
    local mount_name
    mount_name="$(basename "${device}")"
    local target="${TARGET_ROOT}/${mount_name}"

    mkdir -p "${target}" || {
        emit storage_failed '{"reason":"mkdir_failed"}'
        return 1
    }

    # Check if already mounted
    if mountpoint -q "${target}"; then
        log_debug "Already mounted: ${target}"
        return 0
    fi

    # Try bind mount if device is already mounted elsewhere
    local src_mount
    src_mount="$(findmnt -n -o TARGET --source "${device}" 2>/dev/null || true)"

    if [ -n "${src_mount}" ]; then
        mount --bind "${src_mount}" "${target}" || {
            emit storage_failed '{"reason":"bind_failed"}'
            return 1
        }

        emit storage_mounted '{"reason":"bind"}'
        return 0
    fi

    # Detect filesystem type
    local fstype
    fstype="$(blkid -o value -s TYPE "${device}" 2>/dev/null || true)"

    [ -z "${fstype}" ] && {
        emit storage_failed '{"reason":"unknown_fs"}'
        return 1
    }

    local mount_opts="${mode}"

    # Mount based on filesystem type with appropriate options
    if [ "${fstype}" = "ntfs" ]; then
        # Try NTFS with standard options, fallback to ntfs-3g
        mount -t ntfs -o "${mount_opts},uid=0,gid=0,umask=022" "${device}" "${target}" \
        || mount -t ntfs-3g -o "${mount_opts},uid=0,gid=0,umask=022" "${device}" "${target}" \
        || {
            emit storage_failed '{"reason":"ntfs_mount_failed"}'
            return 1
        }
    else
        # Handle different filesystem types with appropriate options
        case "${fstype}" in
            exfat)
                mount -t exfat -o "${mount_opts},uid=0,gid=0,umask=022" "${device}" "${target}" || return 1
                ;;
            vfat|fat|fat32)
                mount -t vfat -o "${mount_opts},uid=0,gid=0,umask=022" "${device}" "${target}" || return 1
                ;;
            *)
                # Generic mount for standard filesystems (ext4, btrfs, etc.)
                mount -t "${fstype}" -o "${mount_opts}" "${device}" "${target}" || return 1
                ;;
        esac
    fi

    # Verify mount was successful
    mountpoint -q "${target}" || {
        emit storage_failed '{"reason":"post_check_failed"}'
        return 1
    }

    emit storage_mounted "{\"reason\":\"direct\",\"fs\":\"${fstype}\"}"
    return 0
}

# === Source Storage Mount ===
# Mount source device (Nextcloud storage) in read-only mode

mount_source() {
    log_debug "mount_source(): ${SOURCE_DEVICE}"
    mount_core "${SOURCE_DEVICE}" "rw"
}

# === Destination Storage Mount ===
# Mount destination device (backup storage) in read-write mode

mount_destination() {
    log_debug "mount_destination(): ${DEST_DEVICE}"
    mount_core "${DEST_DEVICE}" "rw"
}

# === Destination Storage Unmount ===
# Safely unmount destination device if mounted

umount_destination() {
    log_debug "umount_destination(): start"

    # Resolve device - if not found, assume already disconnected
    local device
    device="$(resolve_device "${DEST_DEVICE}")" || {
        log_debug "Device already gone, skip unmount"
        return 0
    }

    # Construct mount point path
    local mount_name
    mount_name="$(basename "${device}")"
    local target="${TARGET_ROOT}/${mount_name}"

    # Unmount if currently mounted
    if mountpoint -q "${target}"; then
        umount "${target}" || return 1
        log_debug "Unmounted ${target}"
    else
        log_debug "Not mounted: ${target}"
    fi
}