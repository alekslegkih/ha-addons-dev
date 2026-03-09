#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Runtime defaults
# ------------------------------------------------------------------

DEVICE=""
TARGET_DIR=""
MAX_COPIES=0
SYNC_EXIST_START=false

# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

load_config() {

  log_debug "load_config(): start"

  bashio::log "Loading config..."

  DEVICE=$(bashio::config 'device' "")
  TARGET_DIR=$(bashio::config 'target_dir' "")
  MAX_COPIES=$(bashio::config 'max_copies' 0)

  if bashio::config.true 'sync_exist_start'; then
      SYNC_EXIST_START=true
  else
      SYNC_EXIST_START=false
  fi

  log_debug "Raw config values:"
  log_debug "  DEVICE=${DEVICE:-empty}"
  log_debug "  TARGET_DIR=${TARGET_DIR:-empty}"
  log_debug "  MAX_COPIES=${MAX_COPIES:-empty}"
  log_debug "  SYNC_EXIST_START=${SYNC_EXIST_START:-empty}"

  # ------------------------------------------------------------------
  # Information output
  # ------------------------------------------------------------------

  if [ -z "${DEVICE}" ]; then
      device="\033[0;33mnot set\033[0m"
  else
      device="\033[0;34m${DEVICE}\033[0m"
  fi

  if [ -z "${TARGET_DIR}" ]; then
      target_dir="\033[0;33mnot set\033[0m"
  else
      target_dir="\033[0;34m${TARGET_DIR}\033[0m"
  fi

  if [ "${SYNC_EXIST_START}" = "true" ]; then
    sync_state="\033[0;32menabled\033[0m"
  else
    sync_state="\033[0;33mdisabled\033[0m"
  fi

  bashio::log "  Device       : ${device}"
  bashio::log "  Target dir   : ${target_dir}"
  bashio::log "  Max backups  : \033[0;34m${MAX_COPIES}\033[0m"
  bashio::log "  Sync state   : ${sync_state}"

  # ------------------------------------------------------------------
  # Validating target directory
  # ------------------------------------------------------------------

    _validate_config

  # ------------------------------------------------------------------
  # Static paths
  # ------------------------------------------------------------------

  SOURCE_DIR="/backup"
  TARGET_ROOT="/mnt"
  QUEUE_FILE="/tmp/backup_sync.queue"

  log_debug "Derived paths:"
  log_debug "  SOURCE_DIR=${SOURCE_DIR}"
  log_debug "  QUEUE_FILE=${QUEUE_FILE}"
  log_debug "  TARGET_ROOT=${TARGET_ROOT}"

  bashio::log.green "Configuration loaded"
  log_debug "load_config(): completed"

}

# ---------------------------------------------------------
# Validate config format
# ---------------------------------------------------------

_validate_config() {

  log_debug "_validate_config(): start"

  # ----------------------------------------------------------
  # Mount point default
  # ----------------------------------------------------------

  if [ -z "${TARGET_DIR}" ]; then
      TARGET_DIR="backups"
      bashio::log.yellow "Target dir not set — using default: ${TARGET_DIR}"
      log_debug "TARGET_DIR fallback applied"
  fi

  # ----------------------------------------------------------
  # Remove leading slashes
  # ----------------------------------------------------------

  if [[ "${TARGET_DIR}" == /* ]]; then
      bashio::log.yellow "Target dir must not start with '/'. Normalizing."
      TARGET_DIR="${TARGET_DIR#/}"
      log_debug "Leading slash removed, TARGET_DIR=${TARGET_DIR}"
  fi

  # ----------------------------------------------------------
  # Prevent path traversal
  # ----------------------------------------------------------

  if [[ "${TARGET_DIR}" == *".."* ]]; then
      bashio::log.red "Target dir must not contain '..'"
      return 1
  fi

  # ----------------------------------------------------------
  # Prevent empty after normalization
  # ----------------------------------------------------------

  if [ -z "${TARGET_DIR}" ]; then
      TARGET_DIR="backups"
      log_debug "Target dir became empty after normalization — using default: ${TARGET_DIR}"
  fi

  log_debug "Final TARGET_DIR=${TARGET_DIR}"
  log_debug "_validate_config(): completed"

  return 0
}
