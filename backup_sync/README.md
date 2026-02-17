# Backup Sync

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/backup_sync/README_RU.md)

Addon for **Home Assistant** designed for automatic synchronization of backups to an external USB drive.

Runs in the background and integrates with Home Assistant via events.

## Features

- Detects newly created backups
- Optionally synchronizes existing files on startup
- Supports limiting the number of stored backups
- Automatically removes old files when the limit is exceeded
- Works fully autonomously

## Configuration

### USB device (`usb_device`)

The USB drive partition that will be used by the addon.  
Example: `sdb1`.

> [!WARNING]
> Specify the disk partition (for example, `sdb1`),  
> not the entire disk name (`sdb`).

### Destination folder (`mount_point`)

Name of the folder inside `/media` where the USB drive will be mounted.  
Default: `/backups`

### Maximum number of copies (`max_copies`)

Number of backups to keep on the USB drive.  
When the limit is exceeded, old files are automatically deleted.

### Sync on startup (`sync_exist_start`)

If enabled, existing files in `/backup` will be checked on addon startup  
and copied to the USB drive if necessary.

## Home Assistant Events

The addon publishes events that can be used in automations.  
List of events:

- `backup_sync.storage_failed`
- `backup_sync.backup_detected`
- `backup_sync.initial_scan_completed`
- `backup_sync.copy_started`
- `backup_sync.copy_completed`
- `backup_sync.error`
- `backup_sync.ready`

### Automation example

```yaml
alias: Disk unavailable
triggers:
  - trigger: event
    event_type: backup_sync.error
    event_data:
      reason: no_device_configured
conditions: []
actions:
  - action: notify.telegram_info
    data:
      title: Backup Sync Error
      message: Disk connection error
mode: single
```

## Debug mode

If the addon does not start or diagnostics are required:

- Create the file:

```bash
/ config/debug.flag
```

- Restart the addon.

Extended logging will be enabled. The addon will not stop even if errors occur.

## Common issues

### No USB device configured

- Make sure the `usb_device` parameter is set correctly  
- Ensure the USB drive is connected  
- Verify that you specified the partition name, not the entire disk  

## License

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](
https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
