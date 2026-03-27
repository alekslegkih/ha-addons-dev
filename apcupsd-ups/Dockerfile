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

# Системные зависимости
RUN apk add --no-cache \
    apcupsd \
    curl

# Права на скрипты
RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/00-init/up \
    /etc/s6-overlay/s6-rc.d/10-apcupsd/run \
    /etc/s6-overlay/s6-rc.d/10-apcupsd/finish \
    /usr/bin/apcupsd_init \
    /usr/bin/apcupsd_run \
    /etc/apcupsd/doshutdown