ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.13-alpine3.23
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_VERSION

# Добавим L4 в Caddy
FROM caddy:builder AS caddy_builder

RUN xcaddy build \
    --with github.com/mholt/caddy-l4

FROM ${BUILD_FROM}

ENV PYTHONUNBUFFERED=1 \
    S6_VERBOSITY=1

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Установка зависимостей
RUN apk add --no-cache openssl

# Копируем Caddy с L4
COPY --from=caddy_builder /usr/bin/caddy /usr/bin/caddy

# Python зависимости
RUN pip install --no-cache-dir flask

# Копируем root в файловую систему
COPY rootfs /

# Права на скрипты
RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/00-init/up \
    /etc/s6-overlay/s6-rc.d/00-init/init \
    /etc/s6-overlay/s6-rc.d/10-caddy/run \
    /etc/s6-overlay/s6-rc.d/10-caddy/finish \
    /etc/s6-overlay/s6-rc.d/20-flask/run
