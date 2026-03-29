import os
import json
import logging
from pathlib import Path
import time

import requests

from events import emit


# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

CONFIG_PATH = "/data/options.json"
OFFSET_FILE = "/data/telegram_offset.txt"


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

    if not cfg.get("token"):
        raise RuntimeError("config: 'token' is required")

    return cfg


CONFIG = load_config()


def cfg(key, default=None):
    return CONFIG.get(key, default)


# ------------------------------------------------------------------
# Transmission
# ------------------------------------------------------------------

trans_cfg = cfg("transmission", {})

trans_host = trans_cfg.get("host")
trans_port = trans_cfg.get("port", 9091)
watch_folder = trans_cfg.get("watch_folder", "/share/watch")

if not trans_host:
    raise RuntimeError("transmission: 'host' is required")

TRANSMISSION_URL = f"http://{trans_host}:{trans_port}/transmission/rpc"

trans_auth = None
if trans_cfg.get("username") and trans_cfg.get("password"):
    trans_auth = (trans_cfg["username"], trans_cfg["password"])

logger.info(f"Transmission: {trans_host}:{trans_port}")


# ------------------------------------------------------------------
# HTTP Session + Proxy
# ------------------------------------------------------------------

# Telegram session
tg_session = requests.Session()

# Local session
local_session = requests.Session()

proxy_cfg = cfg("proxy", {})

if proxy_cfg.get("enabled"):
    proxy_type = proxy_cfg.get("type")
    host = proxy_cfg.get("host")
    port = proxy_cfg.get("port")

    if not proxy_type:
        raise RuntimeError("proxy: 'type' is required when enabled")

    if proxy_type not in ("socks", "http"):
        raise RuntimeError("proxy: 'type' must be 'socks' or 'http'")

    if not host:
        raise RuntimeError("proxy: 'host' is required when enabled")

    if not port:
        raise RuntimeError("proxy: 'port' is required when enabled")

    scheme = "socks5h" if proxy_type == "socks" else "http"

    username = proxy_cfg.get("username")
    password = proxy_cfg.get("password")

    if username and password:
        proxy_url = f"{scheme}://{username}:{password}@{host}:{port}"
    else:
        proxy_url = f"{scheme}://{host}:{port}"

    logger.info(f"Proxy enabled: {scheme}://{host}:{port}")

    tg_session.proxies = {
        "http": proxy_url,
        "https": proxy_url,
    }


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
    r = tg_session.post(url, json=params or {}, timeout=timeout)
    r.raise_for_status()
    return r.json()


def send_message(token, chat_id, text):
    try:
        telegram_api(token, "sendMessage", {
            "chat_id": chat_id,
            "text": text
        })
    except Exception as e:
        logger.warning(f"send_message failed: {e}")


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

        r = local_session.post(
            TRANSMISSION_URL,
            json=payload,
            headers=headers,
            auth=trans_auth,
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
        logger.info(f"{user_name}: invalid file → {filename}")

        send_message(token, msg["chat"]["id"], f"⚠️ {user_name}: не .torrent")

        emit("invalid_input", {
            "type": "file",
            "name": filename,
            "user_name": user_name
        })
        return

    file_id = doc["file_id"]

    file_info = telegram_api(token, "getFile", {"file_id": file_id})
    file_path = file_info["result"]["file_path"]

    file_url = f"https://api.telegram.org/file/bot{token}/{file_path}"
    file_data = tg_session.get(file_url, timeout=30).content

    Path(watch_folder).mkdir(parents=True, exist_ok=True)

    save_path = os.path.join(watch_folder, filename)

    with open(save_path, "wb") as f:
        f.write(file_data)

    logger.info(f"{user_name}: torrent saved → {filename}")

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
        logger.info(f"{user_name}: magnet added")

        send_message(token, msg["chat"]["id"], f"🧲 {user_name}: magnet добавлен")

        emit("magnet_added", {"user_name": user_name})
    else:
        logger.warning(f"{user_name}: magnet failed")

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
                    "timeout": 0
                },
                timeout=10
            )

            last_update_id = None

            for update in updates.get("result", []):
                update_id = update["update_id"]
                msg = update.get("message", {})

                last_update_id = update_id

                user_id = msg.get("from", {}).get("id")

                if user_id not in users:
                    logger.info(f"Unauthorized user: {user_id}")

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

        except requests.exceptions.ReadTimeout:
            continue

        except Exception as e:
            logger.warning(f"Error: {e}")

        time.sleep(10)


if __name__ == "__main__":
    main()
