ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Установка Caddy
RUN apk add --no-cache \
    caddy

# Copy root filesystem
COPY rootfs /

# Права на скрипты
RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/00-init/up \
    /etc/s6-overlay/s6-rc.d/00-init/init \
    /etc/s6-overlay/s6-rc.d/10-caddy/run \
    /etc/s6-overlay/s6-rc.d/10-caddy/finish
