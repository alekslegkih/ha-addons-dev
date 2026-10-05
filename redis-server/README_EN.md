# Redis Server

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/redis-server/README_RU.md)

Add-on for **Home Assistant** that provides a Redis server for use as a cache.

Runs in the background and is intended to be used by other add-ons and services, such as Nextcloud.

## Features

- Lightweight and fast Redis server
- Works as a cache: when memory is full, the oldest keys are evicted
- Persistent storage is disabled — data lives in memory only
- Minimal configuration and easy start
- Port is not exposed externally, accessible only within the Home Assistant network

> [!NOTE]
> This add-on is designed to be used as a cache, not as persistent storage.
> Data is not preserved across restarts — this is expected behavior for a cache.

## Settings

### Maximum memory (`maxmemory`)

Memory limit that Redis is allowed to use.

Example: `128mb`

> If not set, the default value is `128mb`.
> This is enough for home use with a small number of users.

### Eviction policy (`maxmemory_policy`)

What to do when memory is full.

Available values:

- `noeviction` — do not evict, return an error on write
- `allkeys-lru` — evict least recently used keys (recommended for a cache)
- `allkeys-lfu` — evict least frequently used keys
- `allkeys-random` — evict random keys
- `volatile-lru` — evict least recently used keys with a TTL
- `volatile-lfu` — evict least frequently used keys with a TTL
- `volatile-random` — evict random keys with a TTL
- `volatile-ttl` — evict keys with the shortest TTL

Example: `allkeys-lru`

> If not set, the default value is `allkeys-lru`.

## How it works

The add-on starts `redis-server` with a generated configuration.

- Data is stored in RAM only
- Persistent storage (RDB/AOF) is disabled
- When memory fills up, old keys are evicted according to the selected policy
- The server is accessible only from the internal Home Assistant network

To connect another add-on or service, use the **slug of this add-on** as the host, for example:

```php
'host' => 'redis-server',
'port' => 6379,
```

## Common issues

### Another add-on cannot connect

 - Make sure the client is configured with the slug of this add-on, not localhost




## License

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
