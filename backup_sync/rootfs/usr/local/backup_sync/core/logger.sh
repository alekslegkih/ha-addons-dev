#!/usr/bin/env bash

# =========================================================
# Simple pretty logger for Backup Sync addon
# User-friendly by default, debug via /data/debug.flag
# =========================================================

DEBUG_FLAG="/config/debug.flag"

# ---------- Colors ----------
NC="\033[0m"

WHITE=""
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"

# ---------- Timestamp ----------
_ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

# ---------- Debug check ----------
_is_debug() {
    [ -f "${DEBUG_FLAG}" ]
}

# ---------- Core printer ----------
_log_raw() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# =========================================================
# Public API
# =========================================================

# Plain message (white)
log() {
    _log_raw "${WHITE}" "$@"
}

# Success (green)
log_ok() {
    _log_raw "${GREEN}" "$@"
}

# Warning (yellow)
log_warn() {
    _log_raw "${YELLOW}" "$@"
}

# Error (red + timestamp)
log_error() {
    _log_raw "${RED}" "$@"
}

# Section header (blue)
log_section() {
    _log_raw "${BLUE}" "=== $* ==="
}

# Debug (purple + timestamp, only if flag exists)
log_debug() {
    _is_debug || return 0
    _log_raw "${PURPLE}" "[$(_ts)] $*"
}
