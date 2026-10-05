## Configuration

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/backup_sync/DOCS_RU.md)

### USB device (`usb_device`)

The partition of the USB drive that will be used by the add-on.  
Example: `sdb1`.

> [!WARNING]
> Specify the disk partition (e.g., sdb1),  
> not the entire disk name (`sdb`).

### Maximum number of copies (`max_copies`)

The number of backups to store on the USB drive.  
When the limit is exceeded, old files are automatically deleted.

### Sync on startup (`sync_exist_start`)

If enabled, existing files in /backup will be checked when the add-on starts  
and copied to the USB drive if necessary.

## File Browser

- Create folders
- Rename folders and files
- Delete folders and files
- Download files

> [!TIP]  
> To keep a specific backup, move the file into any created folder.  
> After that, the script will no longer "see" the file.  
> This allows you to preserve important copies without downloading them —  
> they won't be deleted when the max_copies limit is exceeded.  
> Automatic cleanup will only work for backups in the root directory.  
> [!NOTE]  
> The file browser only works within the backup directory and has no access to the system or other add-ons.

## Home Assistant Events

The add-on publishes events that can be used in automations.
Main event types:

- Service state: service_state
- Critical disk errors: storage_failed
- Copy service: copy_service

To see all events, filter by the domain ***backup_sync***

### Automation example

```yaml
alias: Disk unavailable
triggers:
  - trigger: event
    event_type: backup_sync.storage_failed
    event_data:
      reason: device_error
conditions: []
actions:
  - action: notify.telegram_info
    data:
      title: ❌ Disk Error
      message: >-
        *Error:* {{ trigger.event.data.error }}
mode: single
```
```yaml
alias: Copy completed
triggers:
  - trigger: event
    event_type: backup_sync.copy_service
    event_data:
      reason: copy_completed
conditions: []
actions:
  - action: notify.telegram_info
    data:
      title: ✅ *Copy completed*
      message: >-        
        *File:* `{{ trigger.event.data.filename }}`
        *Size:* {{ (trigger.event.data.size_bytes | int / 1024 / 1024 / 1024) | round(2) }} GB
        *Time:* {{ trigger.event.data.seconds }} s
        *Speed:* {{ (trigger.event.data.speed_bps | int / 1024 / 1024) | round(1) }} MB/s
mode: single
```

## Debug mode

If the add-on won't start and diagnostics are needed, you can enable debug mode.

- Create the file:

```bash
/ config/debug.flag
```

- Restart the add-on.

In debug mode, logs will show extended information.  
The add-on will freeze in a running state even on critical errors (for diagnostic collection).

> [!TIP]  
> After diagnostics, delete the file and restart the add-on to return to normal mode.

## Common issues

### No USB device configured

- Check that the  `usb_device` parameter is set correctly
- Make sure the drive is connected
- Verify that you specified the partition name, not the entire device
