#!/usr/bin/with-contenv bashio
set -euo pipefail


power_on() {

    log_debug "Power module: enabling disk power"

    if [ "${POWER_ENABLED}" != "true" ]; then
        log_debug "Power management disabled"
        return 0
    fi

    log_debug "Calling HA service switch.turn_on"
    log_debug "Target entity: ${DISK_SWITCH}"

    if bashio::api.supervisor POST \
        /core/api/services/switch/turn_on \
        "{\"entity_id\":\"${DISK_SWITCH}\"}" \
        true
    then
        bashio::log.green "Backup disk power enabled (${DISK_SWITCH})"
        return 0
    fi

    bashio::log.red "Failed to enable backup disk power (${DISK_SWITCH})"
    return 1
}


power_off() {

    log_debug "Power module: disabling disk power"

    if [ "${POWER_ENABLED}" != "true" ]; then
        log_debug "Power management disabled"
        return 0
    fi

    log_debug "Calling HA service switch.turn_off"
    log_debug "Target entity: ${DISK_SWITCH}"

    if bashio::api.supervisor POST \
        /core/api/services/switch/turn_off \
        "{\"entity_id\":\"${DISK_SWITCH}\"}" \
        true
    then
        bashio::log.yellow "Backup disk power disabled (${DISK_SWITCH})"
        return 0
    fi

    bashio::log.red "Failed to disable backup disk power (${DISK_SWITCH})"
    return 1
}