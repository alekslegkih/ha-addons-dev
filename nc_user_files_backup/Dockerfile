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

# Рабочие директория аддона
ENV S6_DIR=/etc/s6-overlay/s6-rc.d
ENV BIN_DIR=/usr/bin
ENV APP_DIR=/usr/local/nc_user_files_backup

# Системные зависимости
RUN apk add --no-cache \
    bash \
    coreutils \
    util-linux \
    jq \
    python3 \
    py3-pip

# Python зависимости
RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    --prefer-binary \
    watchdog \
    requests \
    flask

# Права на скрипты
RUN chmod +x \
    ${S6_DIR}/00-init/up \
    ${S6_DIR}/10-backup/run \
    ${S6_DIR}/20-web/run \
    ${BIN_DIR}/backup_init \
    ${BIN_DIR}/backup_pipeline \
    ${BIN_DIR}/backup_scheduler \
    ${APP_DIR}/core/*.sh \
    ${APP_DIR}/power/*.sh \
    ${APP_DIR}/storage/*.sh \
    ${APP_DIR}/sync/*.sh
