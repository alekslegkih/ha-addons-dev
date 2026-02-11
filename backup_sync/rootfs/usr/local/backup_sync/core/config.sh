#!/command/with-contenv bashio
# shellcheck shell=bash


set -euo pipefail

CONFIG_FILE="/data/options.json"
DEBUG_FLAG="/config/debug.flag"


# ---------------------------------------------------------
# Debug mode check
# ---------------------------------------------------------

_is_debug() {
  [ -f "${DEBUG_FLAG}" ]
}

# ---------------------------------------------------------
# Defaults
# ---------------------------------------------------------

USB_DEVICE=""
MOUNT_POINT=""
MAX_COPIES=0
SYNC_EXIST_START=false

# ---------------------------------------------------------
# Load config
# ---------------------------------------------------------

load_config() {

  if [ ! -f "${CONFIG_FILE}" ]; then
    _config_fail "Config file ${CONFIG_FILE} not found" 
  fi

  log_section "Configuration"
  log "Loading config from ${CONFIG_FILE}..."

  USB_DEVICE="$(jq -r '.usb_device // ""' "${CONFIG_FILE}")"
  MOUNT_POINT="$(jq -r '.mount_point // ""' "${CONFIG_FILE}")"
  MAX_COPIES="$(jq -r '.max_copies // 0' "${CONFIG_FILE}")"
  SYNC_EXIST_START="$(jq -r '.sync_exist_start // false' "${CONFIG_FILE}")"

  _validate_config 
  
  log "-----------------------------------------------------------"
  log "  USB device        : ${USB_DEVICE:-not set}"
  log "  Mount point       : ${MOUNT_POINT}"
  log "  Max backups       : ${MAX_COPIES}"

  [ "${SYNC_EXIST_START}" = "true" ] && sync_state="enabled" || sync_state="disabled"
  log "  Initial sync      : ${sync_state}"
  log "-----------------------------------------------------------"

  log_ok "Configuration loaded"



}

# ---------------------------------------------------------
# Validate config format (NOT logic)
# ---------------------------------------------------------

_validate_config() {

  log_debug "Validating config format"

  # mount_point must not be empty
  if [ -z "${MOUNT_POINT}" ]; then
    _config_fail "mount_point is empty"
  fi

  # mount_point must be a name, not a path
  if [[ "${MOUNT_POINT}" == /* ]]; then
    _config_fail "mount_point must not start with '/' (use name only, e.g. baсkups)"
  fi

  # max_copies must be positive integer
  if ! [[ "${MAX_COPIES}" =~ ^[0-9]+$ ]] || [ "${MAX_COPIES}" -le 0 ]; then
    _config_fail "max_copies must be a positive integer"
  fi

  log_debug "Config format validation passed"
}
