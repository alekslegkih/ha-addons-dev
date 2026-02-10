ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    py3-pip \
    mc

# Python зависимости 
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    watchdog \
    requests

# Права на скрипты
RUN chmod +x \
    /etc/services.d/backup_sync/* \
    /usr/bin/backup_sync.sh \
    /usr/local/backup_sync/core/*.sh \
    /usr/local/backup_sync/storage/*.sh \
    /usr/local/backup_sync/sync/*.sh


