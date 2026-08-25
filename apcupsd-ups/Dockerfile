ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.2
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    S6_USER_BUNDLES=/etc/s6-overlay

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
    "${S6_USER_BUNDLES}/user-bundles.d/00-init/up" \
    "${S6_USER_BUNDLES}/user-bundles.d/10-apcupsd/run" \
    "${S6_USER_BUNDLES}/user-bundles.d/10-apcupsd/finish" \
    "/etc/apcupsd/doshutdown"
#     \
#    "/usr/bin/apcupsd_init" \
#    "/usr/bin/apcupsd_run"
