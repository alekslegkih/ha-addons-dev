#!/usr/bin/env bash
set -uo pipefail

# =========================================================
# Copier worker (single processing engine)
# =========================================================


QUEUE_FILE="/tmp/backup_sync.queue"

SOURCE_DIR="/backup"
TARGET_DIR="/media/${MOUNT_POINT}"

BASE_DIR="/usr/local/backup_sync"
source "${BASE_DIR}/core/logger.sh"

TMP_SUFFIX=".partial"

STABLE_CHECK_INTERVAL=2
STABLE_CHECK_COUNT=3
MAX_RETRIES=3


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

wait_for_stable() {
  local file="$1"

  local last_size=0
  local same_count=0

  log_debug "Waiting for file stabilization: $(basename "${file}")"

  while true; do

    [ -f "${file}" ] || return 1

    local size
    size="$(stat -c %s "${file}")"

    if [ "${size}" -eq "${last_size}" ]; then
      same_count=$((same_count + 1))
    else
      same_count=0
      last_size="${size}"
    fi

    if [ "${same_count}" -ge "${STABLE_CHECK_COUNT}" ]; then
      return 0
    fi

    sleep "${STABLE_CHECK_INTERVAL}"
  done
}


# ---------------------------------------------------------
# Copy one backup
# ---------------------------------------------------------

human_size() {
  numfmt --to=iec --suffix=B "$1"
}


copy_one() {

  local src="$1"
  local name
  name="$(basename "${src}")"

  local tmp="${TARGET_DIR}/${name}${TMP_SUFFIX}"
  local dst="${TARGET_DIR}/${name}"

  local size
  size="$(stat -c %s "${src}")"

  log "Processing backup: ${name} ($(human_size ${size}))"

  local start_ts
  start_ts=$(date +%s)

  if ! wait_for_stable "${src}"; then
    log_error "Source disappeared: ${name}"
    return 1
  fi

  for attempt in $(seq 1 "${MAX_RETRIES}"); do

    log_debug "Copy attempt ${attempt}/${MAX_RETRIES}"

    if cp "${src}" "${tmp}"; then
      mv "${tmp}" "${dst}"

      local end_ts
      end_ts=$(date +%s)

      local duration=$((end_ts - start_ts))
      [ "${duration}" -eq 0 ] && duration=1

      local speed=$((size / duration))

      log_ok "Copied ${name} in ${duration}s ($(human_size ${speed})/s)"

      return 0
    fi

    log_warn "Retrying copy (${attempt})"
    sleep 2
  done

  rm -f "${tmp}"
  log_error "Failed to copy ${name}"

  return 1
}


# ---------------------------------------------------------
# Retention cleanup (INLINE — no external module)
# ---------------------------------------------------------

cleanup_retention() {

  mapfile -t files < <(ls -1t "${TARGET_DIR}"/*.tar* 2>/dev/null || true)

  local total="${#files[@]}"

  if [ "${total}" -le "${MAX_COPIES}" ]; then
    log_debug "Retention: nothing to cleanup"
    return
  fi

  local removed=0

  for ((i=MAX_COPIES; i<total; i++)); do
    rm -f "${files[$i]}"
    ((removed++))
  done

  log "Retention: removed ${removed} old backup(s)"
}



# ---------------------------------------------------------
# Queue helpers
# ---------------------------------------------------------

queue_pop() {

  [ -s "${QUEUE_FILE}" ] || return 1

  read -r line < "${QUEUE_FILE}" || return 1
  sed -i '1d' "${QUEUE_FILE}"

  echo "${line}"
}


# ---------------------------------------------------------
# Main loop
# ---------------------------------------------------------

log_section "Copier worker started"

while true; do

  src="$(queue_pop || true)"

  if [ -z "${src:-}" ]; then
    sleep 2
    continue
  fi

  log_debug "Queue size: $(wc -l < "${QUEUE_FILE}" 2>/dev/null || echo 0)"

  if copy_one "${src}"; then
    cleanup_retention
  else
    log_error "Processing failed: ${src}"
  fi

done

