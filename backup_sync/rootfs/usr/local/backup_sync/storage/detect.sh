#!/usr/bin/env bash

# =========================
# Storage device detection
# /storage/detect.sh
# =========================

set -euo pipefail

SYSTEM_DISKS_REGEX="^(sda|mmcblk0|zram)"
DEBUG_FLAG="/config/debug.flag"

_is_debug() { [ -f "${DEBUG_FLAG}" ]; }

detect_devices() {

  log "Available storage devices"

  lsblk -pn -o NAME,TYPE,FSTYPE,SIZE \
    | while read -r name type fstype size; do

        log_debug "RAW: name=${name} type=${type} fstype=${fstype:-none} size=${size:-none}"

        [ "${type}" != "part" ] && continue

        base_name="$(basename "${name}")"

        if [[ "${base_name}" =~ ${SYSTEM_DISKS_REGEX} ]]; then
          log_debug "Skipping system device ${base_name}"
          continue
        fi

        if [ -z "${fstype}" ]; then
          log_debug "Skipping ${base_name} (no filesystem)"
          continue
        fi

        log_ok "  Found: ${base_name} (${fstype}, ${size})"
    done
}
