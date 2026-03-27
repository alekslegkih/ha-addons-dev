# apcupsd (APC UPS)

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/apcupsd-ups/README_RU.md)

Addon for **Home Assistant** providing an apcupsd-based service for monitoring APC UPS devices.

Runs in the background and integrates with Home Assistant to provide UPS data and perform safe system shutdown.

## Features

- Supports only APC UPS devices via USB (apcupsd)
- Performs safe system shutdown on critical battery level
- Minimal configuration and easy setup

> [!NOTE]  
> The available sensors and diagnostic data may vary depending on the UPS model.  
> This depends on the capabilities of the device and the data provided by apcupsd.

## Configuration

### Shutdown host (`shutdown_host`)

If enabled, the system will be safely shut down  
when the UPS reaches a critical battery level.

### Battery level (`shutdown_battery_level`)

Battery charge percentage at which system shutdown will be triggered.

Example: `10`

### Runtime remaining (`shutdown_runtime`)

Remaining runtime (in minutes) at which system shutdown will be triggered.

Example: `5`

## How it works

The addon uses `apcupsd` to communicate with the UPS via USB.

- Reads UPS status data
- Provides data to Home Assistant
- Initiates safe shutdown when critical conditions are met

## Common issues

### UPS not detected

- Make sure the UPS is connected via USB  

## License

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
