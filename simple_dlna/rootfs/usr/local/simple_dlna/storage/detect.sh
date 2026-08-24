#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


# ------------------------------------------------------------------
# Table helper
# ------------------------------------------------------------------

print_table_row() {

    printf '| %-9.9s | %-16.16s | %-36.36s | %-6.6s | %-10.10s |\n' \
        "$1" \
        "$2" \
        "$3" \
        "$4" \
        "$5"
}

# ------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------

detect_devices() {

    log_debug "detect_devices(): start"

    bashio::log "Available Disks for mounting:"
    echo

    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'

    print_table_row \
        "NAME" \
        "LABEL" \
        "UUID" \
        "SIZE" \
        "FSTYPE"

    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'

    local first_disk=true

    while IFS= read -r line; do

        eval "${line}"

        case "${TYPE}" in
            disk)

                case "${NAME}" in
                    zram*)
                        continue
                        ;;
                esac

                if [ "${first_disk}" = false ]; then
                    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'
                fi

                print_table_row \
                    "${NAME}" \
                    "${LABEL}" \
                    "${UUID}" \
                    "${SIZE}" \
                    "${FSTYPE}"

                first_disk=false
                ;;

            part)

                case "${NAME}" in
                    zram*)
                        continue
                        ;;
                esac

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

    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'

    echo

    log_debug "detect_devices(): completed"
}
