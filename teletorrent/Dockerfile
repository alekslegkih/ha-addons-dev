ARG BUILD_FROM=ghcr.io/home-assistant/base:3.22
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    S6_VERBOSITY=1

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

COPY rootfs /

RUN apk add --no-cache \
    python3 \
    py3-pip \
    ca-certificates \
    && update-ca-certificates

RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    requests[socks]

RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/10-teletorrent/run \
    /etc/s6-overlay/s6-rc.d/10-teletorrent/finish \
    /etc/s6-overlay/s6-rc.d/00-init/up
