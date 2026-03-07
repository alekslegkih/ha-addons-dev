#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

_is_debug() { [ -f "${DEBUG_FLAG}" ]; }

# =========================================================
# Device resolving
# =========================================================

resolve_device() {
  local input="$1"
  local path

  log_debug "Resolving device for: ${input}"

  for path in \
    "/dev/${input}" \
    "/dev/disk/by-label/${input}" \
    "/dev/disk/by-uuid/${input}"
  do
    if [ -b "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  return 1
}


# =========================================================
# Storage validation
# =========================================================

check_storage() {

  log_debug "USB_DEVICE=${USB_DEVICE}"
  log "Connecting to configured USB device..."

  # 1. Device configured?
  if [ -z "${USB_DEVICE}" ]; then
    log_error "No USB device configured"
    emit storage_failed '{"reason":"no_device_configured"}'

    return 1
  fi

  # 2. Resolve device path
  local device
  device="$(resolve_device "${USB_DEVICE}")" || {
    log_error "Device ${USB_DEVICE} not found or not a block device"
    emit storage_failed '{"reason":"not_block_device"}'

    return 1
  }

  log_debug "Resolved device=${device}"

  # 3. Protect system disks
  case "${device}" in
    /dev/sda*|/dev/mmcblk0*|/dev/nvme0n1*)
      log_error "Refusing to use system device: ${device}"
      emit storage_failed '{"reason":"system_device_blocked"}'

      return 1
      ;;
  esac

  # 4. Filesystem detection
  log_debug "Detecting filesystem via lsblk"

  local fstype
  fstype="$(lsblk -no FSTYPE "${device}" 2>/dev/null || true)"

  log_debug "fstype=${fstype:-none}"

  if [ -z "${fstype}" ]; then
    log_error "Filesystem not detected on ${device}"
    emit storage_failed '{"reason":"no_filesystem"}'
    return 1
  fi

  log_ok "Connection successful."
  return 0
}


check_target() {

# =========================================================
# Source check (/backup)
# =========================================================

  log "Checking the source directory..."

  if [ ! -d "/backup" ]; then
    log_error "Source directory /backup does not exist"
    emit storage_failed '{"reason":"source_missing"}'
    return 1
  fi

  log_ok "Source directory /backup found"

# =========================================================
# Target checks
# =========================================================

  local target="/media/${MOUNT_POINT}"

  log_debug "Check target path=${target}"

  # 1. Exists
  if [ ! -d "${target}" ]; then
    log_error "Target directory ${target} does not exist"
    emit storage_failed '{"reason":"target_missing"}'
    return 1
  fi

  # 2. Is mountpoint
  log_debug "Running findmnt --target ${target}"

  if ! findmnt --target "${target}" >/dev/null 2>&1; then
    log_error "Target ${target} is not a mountpoint"
    emit storage_failed '{"reason":"target_not_mounted"}'
    return 1
  fi

  # 3. Writable test
  local testfile="${target}/.write_test"
  log_debug "Writable testfile=${testfile}"

  if ! touch "${testfile}" 2>/dev/null; then
    log_error "Target ${target} is not writable"
    emit storage_failed '{"reason":"target_not_writable"}'
    return 1
  fi

  rm -f "${testfile}"

  return 0
}
