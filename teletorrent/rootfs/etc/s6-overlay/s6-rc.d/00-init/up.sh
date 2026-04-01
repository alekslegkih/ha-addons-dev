#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

cd /app

ADDON_VERSION="$(bashio::addon.version)"
ADDON_NAME="$(bashio::addon.name)"

export ADDON_VERSION
export ADDON_NAME

python3 -m teletorrent.core.config
