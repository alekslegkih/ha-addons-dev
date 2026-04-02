# ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.23
ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    WORKDIR=/usr/local/simple_dlna

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL \
    io.hass.version="VERSION" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Copy root filesystem
COPY rootfs /



RUN apk add --no-cache \
    bash \
    coreutils \
    util-linux \
    lsblk \
    blkid \
    jq \
    python3 \
    py3-pip \
    minidlna \
    ntfs-3g \
    exfatprogs \
    util-linux \
    e2fsprogs

RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    watchdog \
    requests \
    flask


RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/00-init/up \
    /etc/s6-overlay/s6-rc.d/01-service/run \
    /etc/s6-overlay/s6-rc.d/01-service/finish \
    /etc/s6-overlay/s6-rc.d/02-watcher/run \
    /etc/s6-overlay/s6-rc.d/03-manager/run \
    /usr/bin/simple_dlna_init.sh \
    /usr/bin/simple_dlna_service.sh \
    && find /usr/local/simple_dlna -type f -name "*.sh" -exec chmod +x {} \;
