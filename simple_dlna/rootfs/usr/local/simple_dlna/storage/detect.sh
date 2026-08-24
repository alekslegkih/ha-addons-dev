#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------

detect_devices() {

    log_debug "detect_devices(): start"

    bashio::log "Available Disks for mounting:"
    echo

    printf '%-10s %-16s %-38s %-8s %-10s\n' \
        "NAME" "LABEL" "UUID" "SIZE" "FSTYPE"

    printf '%s\n' \
        "--------------------------------------------------------------------------------"

    while IFS= read -r line; do

        eval "${line}"

        case "${TYPE}" in
            disk|part)
                printf '%-10s %-16s %-38s %-8s %-10s\n' \
                    "${NAME}" \
                    "${LABEL}" \
                    "${UUID}" \
                    "${SIZE}" \
                    "${FSTYPE}"
                ;;
        esac

    done < <(
        lsblk -P -n -o NAME,LABEL,UUID,SIZE,FSTYPE,TYPE
    )

    echo

    log_debug "detect_devices(): completed"
}
