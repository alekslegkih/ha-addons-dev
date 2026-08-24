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

    lsblk -rno NAME,LABEL,UUID,SIZE,FSTYPE,TYPE \
        --output-separator '|' \
        | awk -F'|' '
            $6=="part" {
                print $1, $2, $3, $4, $5
            }
        ' \
        | column -t

    echo

    log_debug "Scanning raw lsblk output"

    while IFS='|' read -r name type fstype size label uuid; do

        log_debug \
            "RAW: name=${name} type=${type} fstype=${fstype:-none} size=${size:-none} label=${label:-none} uuid=${uuid:-none}"

        [ "${type}" != "part" ] && continue

        base_name="$(basename "${name}")"

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

        log_debug \
            "Detected device: ${base_name} fstype=${fstype:-none}"

    done < <(
        lsblk -rpn \
            -o NAME,TYPE,FSTYPE,SIZE,LABEL,UUID \
            --output-separator '|'
    )

    log_debug "detect_devices(): completed"
}
