ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.2
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    APP_DIR="/usr/local/backup_sync" \
    S6_USER_BUNDLES="/etc/s6-overlay" \
    READY_FILE="/tmp/service.ready"


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
    "${S6_USER_BUNDLES}/user-bundles.d/01-service/run" \
    "${S6_USER_BUNDLES}/user-bundles.d/02-manager/run" \
    && find "${APP_DIR}" -type f -name "*.sh" -exec chmod +x {} \;

    #    /usr/bin/backup_sync.sh
