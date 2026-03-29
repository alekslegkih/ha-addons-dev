import os
import json
import time
import logging
from pathlib import Path

import requests

from ha_events import emit


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

    # --- defaults ---
    cfg.setdefault("user_ids", [])
    cfg.setdefault("watch_folder", "/share/watch")
    cfg.setdefault("poll_interval", 2)

    # --- validation ---
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

def telegram_api(token, method, params=None):
    url = f"https://api.telegram.org/bot{token}/{method}"
    r = requests.post(url, json=params or {}, timeout=30)
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

def handle_document(token, msg):
    doc = msg["document"]
    filename = doc.get("file_name", "")

    if not filename.endswith(".torrent"):
        send_message(token, msg["chat"]["id"], "⚠️ не .torrent")
        emit("invalid_input", {"type": "file", "name": filename})
        return

    file_id = doc["file_id"]

    file_info = telegram_api(token, "getFile", {"file_id": file_id})
    file_path = file_info["result"]["file_path"]

    file_url = f"https://api.telegram.org/file/bot{token}/{file_path}"
    file_data = requests.get(file_url, timeout=30).content

    save_path = os.path.join(cfg("watch_folder"), filename)

    Path(cfg("watch_folder")).mkdir(parents=True, exist_ok=True)

    with open(save_path, "wb") as f:
        f.write(file_data)

    send_message(token, msg["chat"]["id"], "✅ torrent добавлен")
    emit("torrent_added", {"name": filename})


def handle_text(token, msg):
    text = msg.get("text", "")

    if not text.startswith("magnet:?"):
        return False

    ok = transmission_add(text)

    if ok:
        send_message(token, msg["chat"]["id"], "🧲 magnet добавлен")
        emit("magnet_added", {})
    else:
        send_message(token, msg["chat"]["id"], "❌ ошибка добавления magnet")

    return True


# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------
def main():
    token = cfg("token")
    raw_user_ids = cfg("user_ids", [])

    user_ids = []
    for u in raw_user_ids:
        if not isinstance(u, dict):
            continue

        uid = u.get("id")

        if isinstance(uid, int):
            user_ids.append(uid)

    logger.info("Worker started")

    while True:
        try:
            offset = get_offset()

            updates = telegram_api(token, "getUpdates", {
                "offset": offset + 1,
                "timeout": 30
            })

            last_update_id = None

            for update in updates.get("result", []):
                update_id = update["update_id"]
                msg = update.get("message", {})

                last_update_id = update_id

                user_id = msg.get("from", {}).get("id")

                # strict access
                if user_id not in user_ids:
                    send_message(token, msg["chat"]["id"], "❌ не авторизован")
                    emit("unauthorized_user", {"user_id": user_id})
                    continue  # ❌ убрали set_offset

                if "document" in msg:
                    handle_document(token, msg)

                elif "text" in msg:
                    if not handle_text(token, msg):
                        send_message(token, msg["chat"]["id"], "⚠️ неизвестный ввод")

            if last_update_id is not None:
                set_offset(last_update_id)

        except Exception as e:
            logger.warning(f"Error: {e}")

        time.sleep(cfg("poll_interval"))


if __name__ == "__main__":
    main()
