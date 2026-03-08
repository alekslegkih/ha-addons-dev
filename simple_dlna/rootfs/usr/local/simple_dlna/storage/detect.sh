#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

SYSTEM_DISKS_REGEX="^(sda|mmcblk0|zram)"


# ------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------

detect_devices() {

    log_debug "detect_devices(): start"
    log_debug "System disk regex=${SYSTEM_DISKS_REGEX}"

    bashio::log "Available Disks for mounting:"

    log_debug "Running lsblk (formatted view)"

    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE,TYPE \
        | awk -v regex="${SYSTEM_DISKS_REGEX}" '
            NR==1 { print $1, $2, $3, $4, $5; next }
            $6=="part" && $5!="" && $1 !~ regex {
                print $1, $2, $3, $4, $5
            }
        ' \
        | column -t

    echo

    log_debug "Scanning raw lsblk output"

    while read -r name type fstype size label uuid; do

        log_debug "RAW: name=${name} type=${type} fstype=${fstype:-none} size=${size:-none} label=${label:-none} uuid=${uuid:-none}"

        [ "${type}" != "part" ] && continue

        base_name="$(basename "${name}")"

        if [[ "${base_name}" =~ ${SYSTEM_DISKS_REGEX} ]]; then
            log_debug "Skipping system device ${base_name}"
            continue
        fi

        if [ -z "${fstype}" ]; then
            log_debug "Skipping ${base_name} (no filesystem)"
            continue
        fi

        if [ -z "${label}" ]; then
            log_debug "Label missing for ${base_name}, using blkid fallback"
            label="$(blkid -o value -s LABEL "${name}" 2>/dev/null || true)"
            log_debug "blkid fallback label=${label:-none}"
        fi

        if [ -z "${uuid}" ]; then
            log_debug "UUID missing for ${base_name}, using blkid fallback"
            uuid="$(blkid -o value -s UUID "${name}" 2>/dev/null || true)"
            log_debug "blkid fallback uuid=${uuid:-none}"
        fi

        log_debug "Valid device detected: ${base_name}"

    done < <(lsblk -rpn -o NAME,TYPE,FSTYPE,SIZE,LABEL,UUID)

    log_debug "detect_devices(): completed"
}