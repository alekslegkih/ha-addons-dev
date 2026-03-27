#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


# Define regex for system disks that should be ignored
# Matches primary system devices like root disk, eMMC, and zram
SYSTEM_DISKS_REGEX="^(sda|mmcblk0|zram)"


# Detect and list available block devices suitable for mounting
# Filters out system disks and devices without a filesystem
# Displays a formatted list for user visibility and logs detailed debug info
# Also performs a raw scan to validate and enrich device metadata (LABEL/UUID)
detect_devices() {

    log_debug "detect_devices(): start"
    log_debug "System disk regex=${SYSTEM_DISKS_REGEX}"

    # Print header for user-visible disk list
    bashio::log "Available Disks for mounting:"

    # Run lsblk in formatted (table) mode and filter relevant partitions
    # Keeps only:
    #   - partitions (TYPE=part)
    #   - with filesystem (FSTYPE not empty)
    #   - not matching system disk regex
    log_debug "Running lsblk (formatted view)"
    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE,TYPE \
        | awk -v regex="${SYSTEM_DISKS_REGEX}" '
            NR==1 { print; next }
            $6=="part" && $5!="" && $1 !~ regex
        ' \
        | while IFS= read -r line; do
            bashio::log.blue "  $line"
        done

    echo

    # Perform raw lsblk scan for detailed processing
    # Uses parse-friendly output for scripting
    log_debug "Scanning raw lsblk output"
    while read -r name type fstype size label uuid; do

        log_debug "RAW: name=${name} type=${type} fstype=${fstype:-none} size=${size:-none} label=${label:-none} uuid=${uuid:-none}"

        # Skip non-partition entries
        [ "${type}" != "part" ] && continue

        # Extract base device name (e.g., sdb1 → sdb1)
        base_name="$(basename "${name}")"

        # Skip system disks based on predefined regex
        if [[ "${base_name}" =~ ${SYSTEM_DISKS_REGEX} ]]; then
            log_debug "Skipping system device ${base_name}"
            continue
        fi

        # Skip devices without filesystem
        if [ -z "${fstype}" ]; then
            log_debug "Skipping ${base_name} (no filesystem)"
            continue
        fi

        # Attempt to resolve missing LABEL using blkid
        if [ -z "${label}" ]; then
            log_debug "Label missing for ${base_name}, using blkid fallback"
            label="$(blkid -o value -s LABEL "${name}" 2>/dev/null || true)"
            log_debug "blkid fallback label=${label:-none}"
        fi

        # Attempt to resolve missing UUID using blkid
        if [ -z "${uuid}" ]; then
            log_debug "UUID missing for ${base_name}, using blkid fallback"
            uuid="$(blkid -o value -s UUID "${name}" 2>/dev/null || true)"
            log_debug "blkid fallback uuid=${uuid:-none}"
        fi

        # Final confirmation of valid device
        log_debug "Valid device detected: ${base_name}"

    done < <(lsblk -rpn -o NAME,TYPE,FSTYPE,SIZE,LABEL,UUID)

    log_debug "detect_devices(): completed"
}