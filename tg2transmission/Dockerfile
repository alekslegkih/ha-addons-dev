ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.13-alpine3.23
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV PYTHONUNBUFFERED=1 \
    S6_VERBOSITY=1


LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

COPY rootfs /

RUN pip3 install --no-cache-dir requests

RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/tg2transmission/run \
    /etc/s6-overlay/s6-rc.d/tg2transmission/finish
