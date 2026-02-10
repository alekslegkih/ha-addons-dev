#!/usr/bin/env bash

set -euo pipefail

DEBUG_FLAG="/config/debug.flag"



_is_debug() { [ -f "${DEBUG_FLAG}" ]; }

# ---------------------------------------------------------
# Source + device checks
# ---------------------------------------------------------

check_storage() {

  log_debug "USB_DEVICE=${USB_DEVICE}"
  local device="/dev/${USB_DEVICE}"

  # 1. Device exists
  log "Connecting the selected disk..."

  if [ -z "${USB_DEVICE}" ]; then
    log_error "USB device is not configured"
    log "Please select one of the detected disks in addon settings."
    log_warn "Example: usb_device: sdb1"
    return 1
  fi

  # 2 Must be block device
  log_debug "Check: block device"

  if [ ! -b "${device}" ]; then
    log_error "Device ${device} is not a block device"
    return 1
  fi

  # 3. Protect system disks
  case "${USB_DEVICE}" in
    sda*|mmcblk0*|nvme0n1*)
      log_error "Refusing to use system device: ${USB_DEVICE}"
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
    return 1
  fi

  log_debug "Device ${device} filesystem: ${fstype}"

  log_debug "Check: device path=${device}"

  if [ ! -e "${device}" ]; then
    log_error "Device ${USB_DEVICE} not found"
    log_warn "Make sure the disk name is correct."
    return 1
  fi

  log_ok "Device ${USB_DEVICE} detected and connected."

  # 5. Source directory (/backup)
  log "Checking the source directory..."

  if [ ! -d "/backup" ]; then
    log_error "Source directory /backup does not exist"
    return 1
  fi
  log_ok "Source directory /backup: found"

  return 0
}


# ---------------------------------------------------------
# Target checks
# ---------------------------------------------------------

check_target() {

  local target="/media/${MOUNT_POINT}"

  log_debug "Check target path=${target}"

  # 1. Exists
  if [ ! -d "${target}" ]; then
    log_error "Target directory ${target} does not exist"
    return 1
  fi


  # 2. Is mountpoint
  log_debug "Running findmnt --target ${target}"

  if ! findmnt --target "${target}" >/dev/null 2>&1; then
    log_error "Target ${target} is not a mountpoint"
    return 1
  fi


  # 3. Writable test
  local testfile="${target}/.write_test"
  log_debug "Writable testfile=${testfile}"

  if ! touch "${testfile}" 2>/dev/null; then
    log_error "Target ${target} is not writable"
    return 1
  fi

  rm -f "${testfile}"

  return 0
}
