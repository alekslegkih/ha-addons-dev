#!/usr/bin/env bash

# =========================================================
# Storage device mount
# storage/mount.sh
# Handles direct mount or bind mount of USB device
# =========================================================

set -euo pipefail

mount_usb() {

  local device="/dev/${USB_DEVICE}"
  local target="/media/${MOUNT_POINT}"

  log "Mounting the target directory on the selected disk..."
  log " Device: ${USB_DEVICE}"
  log " Target: ${target}"

  log_debug "mount_usb() start"
  log_debug "device=${USB_DEVICE}"
  log_debug "target=${target}"


  # -------------------------------------------------------
  # Ensure target directory exists
  # -------------------------------------------------------

  if [ ! -d "${target}" ]; then
    log "Creating target directory ${target}"
    log_debug "Running: mkdir -p ${target}"

    mkdir -p "${target}" || {
      log_error "Failed to create target directory ${target}"
      return 1
    }
  fi


  # -------------------------------------------------------
  # 1. Target already mounted
  # -------------------------------------------------------
  log "Checking the target folder..."
  log_debug "Check: findmnt --target ${target}"

  if findmnt --target "${target}" >/dev/null 2>&1; then
    log_ok "Target ${target} is already mounted"
    return 0
  fi


  # -------------------------------------------------------
  # 2. Device already mounted somewhere → bind
  # -------------------------------------------------------

  local src_mount
  src_mount="$(findmnt -n -o TARGET --source "${device}" 2>/dev/null || true)"

  log_debug "src_mount=${src_mount:-none}"

  if [ -n "${src_mount}" ]; then
    log "Device already mounted at ${src_mount}"
    log "Bind-mounting ${src_mount} → ${target}"
    log_debug "Running: mount --bind ${src_mount} ${target}"

    if mount --bind "${src_mount}" "${target}"; then
      log_ok "Bind-mount successful"
      return 0
    else
      log_error "Bind-mount failed"
      return 1
    fi
  fi


  # -------------------------------------------------------
  # 3. Direct mount
  # -------------------------------------------------------

  log "Device not mounted, mounting directly"
  log_debug "Running: mount ${device} ${target}"

  if mount "${USB_DEVICE}" "${target}"; then
    log_ok "Direct mount successful"
    return 0
  fi

  log_error "Failed to mount ${USB_DEVICE} to ${target}"
  return 1
}
