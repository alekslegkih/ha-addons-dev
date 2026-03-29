import os
import json
import time
import logging
from pathlib import Path

import requests

from events import emit


# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

CONFIG_PATH = "/data/options.json"
OFFSET_FILE = "/data/telegram_offset.txt"

TRANSMISSION_URL = "http://addon_core_transmission:9091/transmission/rpc"


# ------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tg2transmission.worker")


# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------

def load_config():
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)

    cfg.setdefault("user_ids", [])
    cfg.setdefault("watch_folder", "/share/watch")
    cfg.setdefault("poll_interval", 2)

    if not cfg.get("token"):
        raise RuntimeError("config: 'token' is required")

    if not isinstance(cfg["user_ids"], list):
        raise RuntimeError("config: 'user_ids' must be a list")

    if not isinstance(cfg["watch_folder"], str):
        raise RuntimeError("config: 'watch_folder' must be a string")

    if not isinstance(cfg["poll_interval"], int):
        raise RuntimeError("config: 'poll_interval' must be int")

    return cfg


CONFIG = load_config()


def cfg(key, default=None):
    return CONFIG.get(key, default)


# ------------------------------------------------------------------
# Offset
# ------------------------------------------------------------------

def get_offset():
    if os.path.exists(OFFSET_FILE):
        return int(open(OFFSET_FILE).read().strip())
    return 0


def set_offset(offset):
    with open(OFFSET_FILE, "w") as f:
        f.write(str(offset))


# ------------------------------------------------------------------
# Telegram API
# ------------------------------------------------------------------

def telegram_api(token, method, params=None, timeout=10):
    url = f"https://api.telegram.org/bot{token}/{method}"
    r = requests.post(url, json=params or {}, timeout=timeout)
    r.raise_for_status()
    return r.json()


def send_message(token, chat_id, text):
    telegram_api(token, "sendMessage", {
        "chat_id": chat_id,
        "text": text
    })


# ------------------------------------------------------------------
# Transmission (magnet)
# ------------------------------------------------------------------

session_id = None


def transmission_add(magnet):
    global session_id

    payload = {
        "method": "torrent-add",
        "arguments": {
            "filename": magnet
        }
    }

    headers = {}

    for _ in range(2):
        if session_id:
            headers["X-Transmission-Session-Id"] = session_id

        r = requests.post(
            TRANSMISSION_URL,
            json=payload,
            headers=headers,
            timeout=10
        )

        if r.status_code == 409:
            session_id = r.headers.get("X-Transmission-Session-Id")
            continue

        r.raise_for_status()
        return True

    return False


# ------------------------------------------------------------------
# Handlers
# ------------------------------------------------------------------

def handle_document(token, msg, user_name):
    doc = msg["document"]
    filename = doc.get("file_name", "")

    if not filename.endswith(".torrent"):
        send_message(token, msg["chat"]["id"], f"⚠️ {user_name}: не .torrent")
        emit("invalid_input", {"type": "file", "name": filename, "user_name": user_name})
        return

    file_id = doc["file_id"]

    file_info = telegram_api(token, "getFile", {"file_id": file_id})
    file_path = file_info["result"]["file_path"]

    file_url = f"https://api.telegram.org/file/bot{token}/{file_path}"
    file_data = requests.get(file_url, timeout=30).content

    watch_folder = cfg("watch_folder")
    Path(watch_folder).mkdir(parents=True, exist_ok=True)

    save_path = os.path.join(watch_folder, filename)

    with open(save_path, "wb") as f:
        f.write(file_data)

    send_message(token, msg["chat"]["id"], f"✅ {user_name}: torrent добавлен")

    emit("torrent_added", {
        "name": filename,
        "user_name": user_name
    })


def handle_text(token, msg, user_name):
    text = msg.get("text", "")

    if not text.startswith("magnet:?"):
        return False

    ok = transmission_add(text)

    if ok:
        send_message(token, msg["chat"]["id"], f"🧲 {user_name}: magnet добавлен")
        emit("magnet_added", {"user_name": user_name})
    else:
        send_message(token, msg["chat"]["id"], f"❌ {user_name}: ошибка добавления magnet")

    return True


# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------

def main():
    token = cfg("token")

    raw_user_ids = cfg("user_ids", [])

    users = {}
    for u in raw_user_ids:
        if not isinstance(u, dict):
            continue

        uid = u.get("id")
        name = u.get("name", str(uid))

        if isinstance(uid, int):
            users[uid] = name

    logger.info("Worker started")

    while True:
        try:
            offset = get_offset()

            updates = telegram_api(
                token,
                "getUpdates",
                {
                    "offset": offset + 1,
                    "timeout": 25
                },
                timeout=35
            )

            last_update_id = None

            for update in updates.get("result", []):
                update_id = update["update_id"]
                msg = update.get("message", {})

                last_update_id = update_id

                user_id = msg.get("from", {}).get("id")

                if user_id not in users:
                    send_message(token, msg["chat"]["id"], "❌ не авторизован")
                    emit("unauthorized_user", {"user_id": user_id})
                    continue

                user_name = users.get(user_id, str(user_id))

                if "document" in msg:
                    handle_document(token, msg, user_name)

                elif "text" in msg:
                    if not handle_text(token, msg, user_name):
                        send_message(token, msg["chat"]["id"], "⚠️ неизвестный ввод")

            if last_update_id is not None:
                set_offset(last_update_id)

        except Exception as e:
            logger.warning(f"Error: {e}")

        time.sleep(cfg("poll_interval"))


if __name__ == "__main__":
    main()
