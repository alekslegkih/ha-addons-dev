#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

# ------------------------------------------------------------------
# Runtime defaults
# ------------------------------------------------------------------

DEVICE=""
MAX_COPIES=0
SYNC_EXIST_START=false

# ------------------------------------------------------------------
# Load config
# ------------------------------------------------------------------

load_config() {

  log_debug "load_config(): start"

  bashio::log "Loading config..."

  DEVICE=$(bashio::config 'device' "")
  MAX_COPIES=$(bashio::config 'max_copies' 0)

  if bashio::config.true 'sync_exist_start'; then
      SYNC_EXIST_START=true
  else
      SYNC_EXIST_START=false
  fi

  log_debug "Raw config values:"
  log_debug "  DEVICE=${DEVICE:-empty}"
  log_debug "  MAX_COPIES=${MAX_COPIES:-empty}"
  log_debug "  SYNC_EXIST_START=${SYNC_EXIST_START:-empty}"

  # ------------------------------------------------------------------
  # Static paths
  # ------------------------------------------------------------------

  SOURCE_DIR="backup"
  TARGET_ROOT="/mnt"
  TARGET_DIR="backups"
  QUEUE_FILE="/tmp/backup_sync.queue"
  TARGET_PATH="${TARGET_ROOT}/${DEVICE}/${TARGET_DIR}"

  log_debug "Derived paths:"
  log_debug "  SOURCE_DIR=${SOURCE_DIR}"
  log_debug "  QUEUE_FILE=${QUEUE_FILE}"
  log_debug "  TARGET_ROOT=${TARGET_ROOT}"
  log_debug "  TARGET_DIR=${TARGET_DIR}"
  log_debug "  TARGET_PATH=${TARGET_PATH}"

  bashio::log.green "Configuration loaded"
  log_debug "load_config(): completed"

  # ------------------------------------------------------------------
  # Information output
  # ------------------------------------------------------------------

  if [ -z "${DEVICE}" ]; then
      device="\033[0;33mnot set\033[0m"
  else
      device="\033[0;34m${DEVICE}\033[0m"
  fi

  source_dir="\033[0;34m${SOURCE_DIR}\033[0m"
  target_dir="\033[0;34m${TARGET_DIR}\033[0m"
  target_path="\033[0;34m${TARGET_PATH}\033[0m"

  if [ "${SYNC_EXIST_START}" = "true" ]; then
    sync_state="\033[0;32menabled\033[0m"
  else
    sync_state="\033[0;33mdisabled\033[0m"
  fi

  bashio::log "  Device       : ${device}"
  bashio::log "  Source dir   : ${source_dir}"
  bashio::log "  Target dir   : ${target_dir}"
  bashio::log "  Target path  : ${target_path}"
  bashio::log "  Max backups  : \033[0;34m${MAX_COPIES}\033[0m"
  bashio::log "  Sync state   : ${sync_state}"


}
