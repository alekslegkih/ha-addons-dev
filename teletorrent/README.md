# Torrent Bridge

[Русская версия](https://github.com/alekslegkih/ha-addons/blob/main/teletorrent/README_RU.md)

An add-on for **Home Assistant** that allows sending `.torrent` files and magnet links from Telegram directly to Transmission.

Runs in the background and automatically processes incoming messages from authorized users.

## Features

- Add `.torrent` files via Telegram
- Access control based on allowed users
- Proxy support (socks / http)
- Integration with Home Assistant via events
- Automatic saving of `.torrent` files to a watch folder
- Magnet link support

## How it works

- The bot receives messages from Telegram
- Verifies the user
- Processes:
  - `.torrent` → saves to folder
  - `magnet` → sends to Transmission
- Sends a response back to the user in Telegram
- Generates an event in Home Assistant

## Configuration

### Telegram

- **token** — Telegram bot token (@BotFather)
- **user_ids** — list of allowed users  
  - **user_name** — friendly name  
  - **user_id** — Telegram user ID  

### Proxy (optional)

Used when Telegram is not directly accessible.

- **enabled** — enable proxy  
- **type** — proxy type (`socks` or `http`)  
- **host** — proxy address  
- **port** — proxy port  
- **username / password** — authentication credentials (if required)  

### Transmission

- **host** — IP address or service name of Transmission  
- **port** — RPC port (default: `9091`)  
- **username / password** — if authentication is enabled  
- **watch_folder** — folder for `.torrent` files (default: `/share/watch`)  

## Common issues

### Telegram not working

- Make sure the bot token is correct
- Check if Telegram is accessible from your network
- If using a proxy — verify its configuration

---

### No response to messages

- Check that your `user_id` is included in `user_ids`
- Make sure the bot is not blocked and can receive messages

---

### Torrent or magnet not added

- Check connection to Transmission
- Verify settings (`host`, `port`)
- Make sure the RPC endpoint is accessible
- Check authentication (if enabled)

---

### Proxy error

- Verify proxy type (`socks` or `http`)
- Make sure proxy host and port are correct
- If authentication is used, check username and password

## License

[![Addon License: MIT](https://img.shields.io/badge/Addon%20License-MIT-green.svg)](https://github.com/alekslegkih/ha-addons/blob/main/LICENSE)
