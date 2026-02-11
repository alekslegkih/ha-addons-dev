#!/usr/bin/env bash

notify() {
    python3 "${BASE_DIR}/notify/ha_notify.py" "$@" || true
}

