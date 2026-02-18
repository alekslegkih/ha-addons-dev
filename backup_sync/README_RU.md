# Backup Sync

[English version](https://github.com/alekslegkih/ha-addons/blob/main/backup_sync/README.md)

Аддон для **Home Assistant**, предназначенный для автоматической синхронизации резервных копий на внешний USB-накопитель.

Работает в фоновом режиме и интегрируется с Home Assistant через события.

## Возможности

- Отслеживает появление новых резервных копий
- Опционально синхронизирует существующие файлы при запуске
- Поддерживает ограничение количества хранимых копий
- Автоматически удаляет старые файлы при превышении лимита
- Работает полностью автономно

## Настройки

### USB-устройство (`usb_device`)

Раздел USB-накопителя, который будет использоваться аддоном.  
Пример: `sdb1`.

> [!WARNING]
> Указывайте именно раздел диска (например, `sdb1`),  
> а не имя всего диска (`sdb`).

### Папка назначения (`mount_point`)

Имя папки внутри `/media`, в которую будет смонтирован USB-накопитель.  
По умолчанию: `/backups`

### Максимальное количество копий (`max_copies`)

Количество резервных копий, которые будут храниться на USB-накопителе.  
При превышении лимита старые файлы автоматически удаляются.

### Синхронизация при запуске (`sync_exist_start`)

Если параметр включён, при старте аддона существующие файлы из `/backup` будут проверены  
и при необходимости скопированы на USB-накопитель.

## События Home Assistant

Аддон публикует события, которые можно использовать в автоматизациях.  
Список событий:

- `backup_sync.storage_failed`
- `backup_sync.backup_detected`
- `backup_sync.initial_scan_completed`
- `backup_sync.copy_started`
- `backup_sync.copy_completed`
- `backup_sync.error`
- `backup_sync.ready`

### Пример автоматизации

```yaml
alias: Диск недоступен
triggers:
  - trigger: event
    event_type: backup_sync.error
    event_data:
      reason: no_device_configured
conditions: []
actions:
  - action: notify.telegram_info
    data:
      title: Ошибка Backup Sync
      message: Ошибка подключения диска
mode: single
```

## Debug-режим

Если аддон не запускается или требуется диагностика:

- Создайте файл:

```bash
/config/debug.flag
```

- Перезапустите аддон.

Будет включено расширенное логирование. Аддон не будет останавливаться даже при возникновении ошибок.

## Частые проблемы

### No USB device configured

- Проверьте, что параметр `usb_device` указан корректно  
- Убедитесь, что диск подключён  
- Проверьте, что указано имя раздела, а не всего устройства  

## Лицензия

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](
https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
