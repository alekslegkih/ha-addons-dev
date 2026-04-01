ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.13-alpine3.23
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    S6_VERBOSITY=1 \
    BUILD_VERSION="${BUILD_VERSION}"

LABEL \
    io.hass.version="${VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

COPY rootfs /

RUN apk add --no-cache ca-certificates && update-ca-certificates mc

RUN pip3 install --no-cache-dir requests[socks]

RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/10-teletorrent/run \
    /etc/s6-overlay/s6-rc.d/10-teletorrent/finish \
    /etc/s6-overlay/s6-rc.d/00-init/up
