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

    printf '+-------+--------+--------------------------------------+--------+----------+\n'

    print_table_row \
        "NAME" \
        "LABEL" \
        "UUID" \
        "SIZE" \
        "FSTYPE"

    printf '+-------+--------+--------------------------------------+--------+----------+\n'

    while IFS= read -r line; do

        eval "${line}"

        case "${TYPE}" in
            disk|part)
                print_table_row \
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

    printf '+-------+--------+--------------------------------------+--------+----------+\n'

    echo

    log_debug "detect_devices(): completed"
}
