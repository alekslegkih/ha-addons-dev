# Simple DLNA Documentation

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/simple_dlna/README_RU.md)

## How it works

On the first start the add-on:

- creates the configuration file minidlna.conf
- initializes the media database
- starts the DLNA server in foreground mode

On subsequent starts:

- the existing media database is reused
- the saved configuration is reused
- the server automatically monitors filesystem changes

ReadyMedia uses the inotify mechanism, so new files automatically appear
in the media library without restarting the server.

The media library directory is created on the selected USB storage device.

The add-on configuration defines the storage parameters:

```bash
device — disk where the media library will be stored
media_dir — name of the media library directory on that disk
```

> [!TIP]  
> If the media library directory does not exist, the add-on will create it automatically.

You can also configure the server name and the minidlna log level.

## How to select a USB disk

The add-on works only with external disks connected to the system.

If the device parameter is not specified, the add-on will print a list
of available disks during startup.

The list of available disks can be found in the add-on logs.

Example:

```bash
NAME      LABEL      UUID                                   SIZE   FSTYPE
sdb1      MEDIA      5b60a136-0d03-4c26-aba5-2bd5b97ece35    6T     ext4
sdc1      BACKUP     2A34-19F0                               2T     exfat
```

A disk can be specified in three different ways:

- By device name  
  - device: sdb1
- By disk label  
  - device: MEDIA
- By filesystem UUID  
  - device: 5b60a136-0d03-4c26-aba5-2bd5b97ece35

## Configuration

The minidlna.conf file is created automatically. It contains two sections
and is stored in the add-on directory.

### Managed section

This section is generated automatically from the add-on configuration.

```conf
***<<< SIMPLE_DLNA-MANAGED-START >>>***
friendly_name=${FRIENDLY_NAME}
media_dir=${DLNA_DIR}
db_dir=${DB_DIR}
port=8200
log_level=general=${LOG_LEVEL}
***<<< SIMPLE_DLNA-MANAGED-END >>>***
```

This part of the configuration is rewritten on every add-on start
and should not be edited manually.

### User section

Below is the user configuration section of ReadyMedia.

```conf
***--- USER CONFIGURATION AREA ---***
inotify=yes
notify_interval=900
strict_dlna=no
album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg/AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg/Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg
```

This section can be edited manually.
Changes will be applied after restarting the add-on.

## Network and access

DLNA uses the SSDP broadcast protocol,
so the add-on runs in host_network mode.

Support for media formats depends on the DLNA client
(TV, media player, or application).

A standard ReadyMedia statistics web interface is also available,
which shows:

- connected clients
- number of files in the media library
- server status

Statistics web interface port: 8200

## File browser

The add-on includes a built-in file browser for managing the media library.

It allows you to:

- upload files
- delete files
- rename files
- move files between folders
- create directories

The file browser works only inside the media library directory
and does not provide access to other Home Assistant directories.

## Supported formats

ReadyMedia does not perform media transcoding.

Supported formats depend on the DLNA client
(TV, media player, or application).

## Features and limitations

- The add-on is intended for use in a local network
- Authentication is not supported
- Encryption is not used
- Media transcoding is not performed
- Supported formats depend on the DLNA client
