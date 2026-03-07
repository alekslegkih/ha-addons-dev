#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -euo pipefail

SYSTEM_DISKS_REGEX="^(sda|mmcblk0|zram)"

detect_devices() {

    log "Available Disks for mounting:"

    lsblk -o NAME,LABEL,UUID,SIZE,FSTYPE,TYPE \
        | awk -v regex="${SYSTEM_DISKS_REGEX}" '
            NR==1 { print $1, $2, $3, $4, $5; next }
            $6=="part" && $5!="" && $1 !~ regex {
                print $1, $2, $3, $4, $5
            }
        ' \
        | column -t


    echo

    while read -r name type fstype size label uuid; do

        log_debug "RAW: name=${name} type=${type} fstype=${fstype:-none} size=${size:-none} label=${label:-none} uuid=${uuid:-none}"

        [ "$type" != "part" ] && continue

        base_name="$(basename "$name")"

        if [[ "$base_name" =~ $SYSTEM_DISKS_REGEX ]]; then
            log_debug "Skipping system device ${base_name}"
            continue
        fi

        if [ -z "$fstype" ]; then
            log_debug "Skipping ${base_name} (no filesystem)"
            continue
        fi

        # fallback если label пуст
        if [ -z "$label" ]; then
            label="$(blkid -o value -s LABEL "$name" 2>/dev/null || true)"
            log_debug "blkid fallback label=${label:-none}"
        fi

        # fallback если uuid пуст
        if [ -z "$uuid" ]; then
            uuid="$(blkid -o value -s UUID "$name" 2>/dev/null || true)"
            log_debug "blkid fallback uuid=${uuid:-none}"
        fi

        log_debug "Valid device detected: ${base_name}"

    done < <(lsblk -rpn -o NAME,TYPE,FSTYPE,SIZE,LABEL,UUID)
}
