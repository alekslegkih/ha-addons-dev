ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL \
    io.hass.version="VERSION" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Copy root filesystem
COPY rootfs /

# Рабочая директория аддона
WORKDIR /usr/local/backup_sync

# Системные зависимости
RUN apk add --no-cache \
    bash \
    coreutils \
    util-linux \
    lsblk \
    blkid \
    jq \
    python3 \
    py3-pip

# Python зависимости
RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    watchdog \
    requests \
    flask

# Права на скрипты
RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/01-service/run \
    /etc/s6-overlay/s6-rc.d/02-manager/run \
    /usr/bin/backup_sync.sh \
    /usr/local/backup_sync/core/*.sh \
    /usr/local/backup_sync/storage/*.sh \
    /usr/local/backup_sync/sync/*.sh
