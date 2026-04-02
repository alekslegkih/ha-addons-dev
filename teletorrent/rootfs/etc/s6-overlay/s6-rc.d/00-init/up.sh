#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -eu

# Читаем имя и версию
ADDON_VERSION="$(bashio::addon.version)"
ADDON_NAME="$(bashio::addon.name)"

# Сохраним в envdir
write_env() {
  printf %s "$2" > "/run/s6/container_environment/$1"
}

write_env ADDON_NAME "$ADDON_NAME"
write_env ADDON_VERSION "$ADDON_VERSION"

# Подготовим окружение
cd /app
python3 -m teletorrent.core.config
