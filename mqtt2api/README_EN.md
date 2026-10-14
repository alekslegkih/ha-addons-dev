# MQTT2API

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/mqtt2api/README.md)

A **Home Assistant** add-on providing a bidirectional bridge between MQTT
and HTTP API / WebSocket.

Designed for IoT devices: it receives data from MQTT, exposes it to external
clients via API and WebSocket, and allows sending commands back to MQTT.

## Features

- Bidirectional bridge: MQTT ⇄ HTTP API / WebSocket
- Automatic connection to the Home Assistant broker via Supervisor
- TLS using certificates from `/ssl`
- Subscriptions to `data`, `state`, `warnings` topics with module filtering
- Command publishing to `<module>/<device_id>/cmd`
- Bearer token authentication
- Real-time event streaming via WebSocket

> [!NOTE]
> The add-on does not store message history. WebSocket clients only receive
> events that occur after they connect.

## Configuration

### API secret (`api_secret`)

Bearer token required for all protected API methods and WebSocket.
Example: `MU_SECRET`

### Modules (`modules`)

Whitelist of top-level MQTT topic segments.
Example: `["fridge", "relay"]`

> [!WARNING]
> At least one topic must be specified.

### TLS certificate (`certfile`)

Path to the TLS certificate in PEM format inside the container.
Default: `/ssl/fullchain.pem`

### TLS key (`keyfile`)

Path to the TLS private key in PEM format inside the container.
Default: `/ssl/privkey.pem`

### Log level (`log_level`)

Allowed values: `debug`, `info`, `warning`, `error`, `fatal`, `off`.
Default: `warning`

## API

The add-on provides an HTTP API and a WebSocket interface for external clients.
Authentication uses a Bearer token configured via the `api_secret` option.

- **Device state** — current readings, status and data freshness
- **Command sending** — publishes a command to the device's MQTT topic
- **WebSocket** — real-time event stream: broker connection, new data,
  state changes, warnings
- **Health check** — service liveness probe without authentication

## How it works

The add-on connects to the MQTT broker via the Home Assistant Supervisor API.
Once connected to the broker, it subscribes to the topics listed in `modules`
and broadcasts incoming messages to all active WebSocket connections. The
HTTP methods `/api/state` and `/api/command` operate on the same dataset.

## Common issues

- `modules is empty`:
    - Add at least one module to the `modules` list

- `TLS file not found`
    - Set correct paths in the `certfile` and `keyfile` options
    - Make sure the certificate and key are valid

- `module_not_enabled` in API response
    - The requested module is not in the `modules` list in the add-on
      configuration

## License

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](
https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
