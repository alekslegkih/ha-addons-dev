#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# Enable strict bash mode: exit on error, undefined variables, and pipe failures
set -euo pipefail

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

emit() {
    log_debug "Emit called with args: $*"
    python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || {
        log_debug "Emit failed (ignored)"
        true
    }
}

# === Home Assistant API Helpers ===
# Wrapper functions for interacting with Home Assistant Supervisor API

# Call any Home Assistant service
# Arguments:
#   $1 - service domain (e.g., 'switch', 'light')
#   $2 - service name (e.g., 'turn_on', 'turn_off')
#   $3 - entity ID to control
# Returns: HTTP status code from the API call
ha_call_service() {
    local domain="$1"
    local service="$2"
    local entity="$3"

    curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"entity_id\":\"${entity}\"}" \
        "http://supervisor/core/api/services/${domain}/${service}"
}

# Check if an entity exists and is accessible in Home Assistant
# Arguments:
#   $1 - entity ID to check
# Returns: HTTP status code (200 if exists, 404 if not found)
ha_check_entity() {
    local entity="$1"

    curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/core/api/states/${entity}"
}

# === Power Control Functions ===
# Manage backup disk power through Home Assistant switches

# Turn on power to the backup disk
# Returns: 0 on success, 1 on failure
power_on() {
    log_debug "Power module: enabling disk power"

    # Skip if power management is disabled in configuration
    if [ "${POWER_ENABLED}" != "true" ]; then
        log_debug "Power management disabled"
        return 0
    fi

    log_debug "Checking entity: ${DISK_SWITCH}"

    # Verify that the configured switch entity exists in Home Assistant
    local check_code
    check_code="$(ha_check_entity "${DISK_SWITCH}")"

    if [ "${check_code}" != "200" ]; then
        bashio::log.red "Switch entity not found: ${DISK_SWITCH}"
        return 1
    fi

    log_debug "Calling HA service: switch.turn_on"

    # Send command to turn on the switch
    local call_code
    call_code="$(ha_call_service switch turn_on "${DISK_SWITCH}")"

    if [ "${call_code}" != "200" ]; then
        bashio::log.red "Failed to call switch.turn_on (HTTP ${call_code})"
        return 1
    fi

    bashio::log.green "Backup disk power enabled"
}

# Turn off power to the backup disk
# Returns: 0 on success, 1 on failure
power_off() {
    log_debug "Power module: disabling disk power"

    # Skip if power management is disabled in configuration
    if [ "${POWER_ENABLED}" != "true" ]; then
        log_debug "Power management disabled"
        return 0
    fi

    log_debug "Calling HA service: switch.turn_off"
    log_debug "Target entity: ${DISK_SWITCH}"

    # Send command to turn off the switch
    local http_code
    http_code="$(ha_call_service switch turn_off "${DISK_SWITCH}")"

    log_debug "HA API response code: ${http_code}"

    if [ "${http_code}" = "200" ]; then
        bashio::log.green "Backup disk power disabled"
        return 0
    fi

    bashio::log.red "Failed to disable backup disk power (${DISK_SWITCH}), HTTP ${http_code}"
    return 1
}