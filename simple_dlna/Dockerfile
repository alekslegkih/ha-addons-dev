ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.2
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

ENV S6_VERBOSITY=1 \
    WORKDIR=/usr/local/simple_dlna \
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
    e2fsprogs

RUN python3 -m pip install --no-cache-dir \
    --break-system-packages \
    --root-user-action=ignore \
    watchdog \
    requests \
    flask


RUN chmod +x \
    ${S6_USER_BUNDLES}/user-bundles.d/00-init/up \
    ${S6_USER_BUNDLES}/user-bundles.d/01-service/run \
    ${S6_USER_BUNDLES}/user-bundles.d/01-service/finish \
    ${S6_USER_BUNDLES}/user-bundles.d/02-watcher/run \
    ${S6_USER_BUNDLES}/user-bundles.d/03-manager/run \
    ${S6_USER_BUNDLES}/scripts/init.sh \
    /usr/bin/simple_dlna_init.sh \
    /usr/bin/simple_dlna_service.sh \
    && find /usr/local/simple_dlna -type f -name "*.sh" -exec chmod +x {} \;
