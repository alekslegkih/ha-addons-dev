#!/command/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail


# ------------------------------------------------------------------
# Table helper
# ------------------------------------------------------------------

CYAN='\033[36m'
RESET='\033[0m'

print_table_row() {
    printf "${CYAN}| %-9.9s | %-12.12s | %-36.36s | %-6.6s | %-8.8s |${RESET}\n" \
        "$1" \
        "$2" \
        "$3" \
        "$4" \
        "$5"
}

print_table_separator() {
    printf "${CYAN}+-----------+--------------+--------------------------------------+--------+----------+${RESET}\n"
}

# ------------------------------------------------------------------
# Device detection
# ------------------------------------------------------------------

detect_devices() {

    log_debug "detect_devices(): start"

    bashio::log.cyan "Available Disks for mounting:"
    echo

    print_table_separator

    print_table_row \
        "NAME" \
        "LABEL" \
        "UUID" \
        "SIZE" \
        "FSTYPE"

    print_table_separator

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
                    print_table_separator
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

    print_table_separator

    echo

    log_debug "detect_devices(): completed"

}
