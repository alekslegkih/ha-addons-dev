#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------

detect_devices() {

    log_debug "detect_devices(): start"

    bashio::log "Available Disks for mounting:"

    log_debug "Running lsblk (formatted view)"

    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE

    echo

    log_debug "Scanning raw lsblk output"

    while read -r line; do

        eval "${line}"

        log_debug \
            "RAW: name=${NAME} type=${TYPE} fstype=${FSTYPE:-none} size=${SIZE:-none} label=${LABEL:-none} uuid=${UUID:-none}"

        [ "${TYPE}" != "part" ] && continue

        base_name="$(basename "${NAME}")"

        if [ -z "${LABEL}" ]; then
            log_debug "Label missing for ${base_name}, using blkid fallback"

            LABEL="$(blkid -o value -s LABEL "${NAME}" 2>/dev/null || true)"

            log_debug "blkid fallback label=${LABEL:-none}"
        fi

        if [ -z "${UUID}" ]; then
            log_debug "UUID missing for ${base_name}, using blkid fallback"

            UUID="$(blkid -o value -s UUID "${NAME}" 2>/dev/null || true)"

            log_debug "blkid fallback uuid=${UUID:-none}"
        fi

        log_debug "Detected device: ${base_name}"

    done < <(
        lsblk -rpnP -o NAME,TYPE,FSTYPE,SIZE,LABEL,UUID
    )

    log_debug "detect_devices(): completed"
}
