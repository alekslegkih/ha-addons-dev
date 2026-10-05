ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    S6_USER_BUNDLES=/etc/s6-overlay/user-bundles.d

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
    redis

# Права на скрипты
RUN chmod +x \
    "${S6_USER_BUNDLES}/00-init/up" \
    "${S6_USER_BUNDLES}/10-redis/run" \
    "${S6_USER_BUNDLES}/10-redis/finish"

