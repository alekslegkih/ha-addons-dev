ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.13-alpine3.23
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    S6_USER_BUNDLES=/etc/s6-overlay

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL \
    io.hass.version="VERSION" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

COPY rootfs /

RUN python3 -m pip install --no-cache-dir \
        --break-system-packages \
        --root-user-action=ignore \
        "aiohttp>=3.11,<4" \
        "aiomqtt>=2.3,<3"

RUN chmod +x \
    "${S6_USER_BUNDLES}/user-bundles.d/mqtt2api/run" \
    "${S6_USER_BUNDLES}/user-bundles.d/mqtt2api/finish"
