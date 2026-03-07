# Changelog

## 0.2.5

- Added translations.

## 0.3.0

- Support mounting by LABEL and UUID.
- Added UUID to storage detection output.
- Improved validation, mounting logic, and error handling.
- Added Home Assistant event-based notification system.

## 0.4.0

- Reworked internal service architecture (s6-rc longrun).
- Improved startup and shutdown handling.
- Reduced system log noise.
- Fixed USB mount handling.

## 0.4.1

- Fixed device resolution failure when debug mode is enabled.
- Improved stability of storage detection logic.

## 0.4.2

- Implemented storage failure detection during copy operations.
- Added automatic shutdown on USB disconnection.
- Improved copy timeout handling to prevent stalled transfers.
- Enhanced backup processing telemetry (size, duration, speed).
- Improved stabilization phase visibility during large backup creation.
