#!/usr/bin/env bash

# =========================================================
# Addon configuration loader
# core/config.sh
#
# Responsibilities:
#   - load options.json
#   - set global config variables
#   - validate config format (not logic)
# =========================================================

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
NOTIFY_SERVICE=""


# ---------------------------------------------------------
# Load config
# ---------------------------------------------------------

load_config() {

  if [ ! -f "${CONFIG_FILE}" ]; then
    _config_fail "Config file ${CONFIG_FILE} not found"
  fi

  log "Loading config from ${CONFIG_FILE}..."

  USB_DEVICE="$(jq -r '.usb_device // ""' "${CONFIG_FILE}")"
  MOUNT_POINT="$(jq -r '.mount_point // ""' "${CONFIG_FILE}")"
  MAX_COPIES="$(jq -r '.max_copies // 0' "${CONFIG_FILE}")"
  SYNC_EXIST_START="$(jq -r '.sync_exis_start // false' "${CONFIG_FILE}")"
  NOTIFY_SERVICE="$(jq -r '.notify_service // ""' "${CONFIG_FILE}")"

  _validate_config

  log_ok "Config loaded successfully"
  log_ok "------------------------------------------------"
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
    _config_fail "mount_point must not start with '/' (use name only, e.g. baskups)"
  fi

  # max_copies must be positive integer
  if ! [[ "${MAX_COPIES}" =~ ^[0-9]+$ ]] || [ "${MAX_COPIES}" -le 0 ]; then
    _config_fail "max_copies must be a positive integer"
  fi

  log_debug "Config format validation passed"
}
