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

    log_debug "Running lsblk device scan"

    while IFS= read -r line; do

        log_debug "lsblk raw: ${line}"

        eval "${line}"

        log_debug "Parsed: NAME=${NAME:-none} TYPE=${TYPE:-none} LABEL=${LABEL:-none} UUID=${UUID:-none} SIZE=${SIZE:-none} FSTYPE=${FSTYPE:-none}"

        case "${TYPE}" in
            disk)

                case "${NAME}" in
                    zram*)
                        log_debug "Skipping zram device: ${NAME}"
                        continue
                        ;;
                esac

                if [ "${first_disk}" = false ]; then
                    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'
                fi

                log_debug "Printing disk: ${NAME}"

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
                        log_debug "Skipping zram partition: ${NAME}"
                        continue
                        ;;
                esac

                log_debug "Printing partition: ${NAME}"

                print_table_row \
                    "${NAME}" \
                    "${LABEL}" \
                    "${UUID}" \
                    "${SIZE}" \
                    "${FSTYPE}"
                ;;

            *)
                log_debug "Skipping unsupported device type: ${TYPE:-none} (${NAME:-unknown})"
                ;;
        esac

    done < <(
        lsblk -P -n -o NAME,LABEL,UUID,SIZE,FSTYPE,TYPE
    )

    printf '+-----------+------------------+--------------------------------------+--------+------------+\n'

    echo

    log_debug "detect_devices(): completed"
}
