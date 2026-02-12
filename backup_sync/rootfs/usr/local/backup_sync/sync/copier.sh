#!/usr/bin/env bash

set -uo pipefail

TARGET_DIR="/${TARGET_ROOT}/${MOUNT_POINT}"

source "${BASE_DIR}/core/logger.sh"

emit() {
  python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || true
}


# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------

now() {
    date +%s
}

human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"
}

queue_pop() {
    [ -s "${QUEUE_FILE}" ] || return 1

    IFS= read -r line < "${QUEUE_FILE}" || return 1
    sed -i '1d' "${QUEUE_FILE}"

    echo "${line}"
}

wait_stable() {
    local f="$1"
    local s1 s2 stable=0

    while [ $stable -lt 3 ]; do
        s1=$(stat -c %s "$f" 2>/dev/null || echo 0)
        sleep 2
        s2=$(stat -c %s "$f" 2>/dev/null || echo 0)

        if [ "$s1" -eq "$s2" ]; then
            stable=$((stable + 1))
        else
            stable=0
        fi
    done
}

cleanup_old() {
    [ "${MAX_COPIES}" -le 0 ] && return 0

    local count
    count=$(ls -1t "${TARGET_DIR}"/*.tar* 2>/dev/null | wc -l || echo 0)

    while [ "${count}" -gt "${MAX_COPIES}" ]; do
        old=$(ls -1t "${TARGET_DIR}"/*.tar* | tail -n 1)
        log_warn " • Removing old backup: $(basename "$old")"
        rm -f "$old"
        count=$((count - 1))
    done
}

copy_one() {
    local src="$1"
    local name tmp size
    local wait_start wait_end wait_sec
    local copy_start copy_end copy_sec speed

    name="$(basename "$src")"
    tmp="${TARGET_DIR}/.${name}.tmp"

    log_section "Backup copy processing"
    log "Backup detected: ${name}"

    # -------------------------
    # stabilization phase
    # -------------------------
    log " • Waiting for file stabilization..."
    
    wait_start=$(now)
    wait_stable "$src"
    wait_end=$(now)
    wait_sec=$((wait_end - wait_start))

    size=$(stat -c %s "$src" 2>/dev/null || echo 0)
    log " • File stabilized (${wait_sec}s)"
    emit copy_started "{\"filename\":\"${name}\",\"size_bytes\":${size}}"

    # -------------------------
    # copy phase
    # -------------------------
    log " • Copying..."

    copy_start=$(now)

    if ! cp "$src" "$tmp"; then
        log_error " ✗ Copy failed"
        rm -f "$tmp"
        emit error "{\"filename\":\"${name}\",\"reason\":\"copy_failed\"}"
        return 1
    fi

    mv "$tmp" "${TARGET_DIR}/${name}"

    copy_end=$(now)
    copy_sec=$((copy_end - copy_start))
    [ "$copy_sec" -le 0 ] && copy_sec=1

    speed=$((size / copy_sec))

    log_ok " ✓ Done ($(human_size "$size")) in ${copy_sec}s ($(human_size "$speed")/s)"
    emit copy_completed "{\"filename\":\"${name}\",\"size_bytes\":${size},\"seconds\":${copy_sec},\"speed_bps\":${speed}}"

    cleanup_old
    return 0
}

# ---------------------------------------------------------
# main loop
# ---------------------------------------------------------

log_ok "Copier worker started"

while true; do
    file=$(queue_pop || true)

    if [ -z "${file:-}" ]; then
        sleep 2
        continue
    fi

    copy_one "$file"
done
