import time
import base64
import re
import requests

from teletorrent.core.logger import get_logger

logger = get_logger(__name__)


# ------------------------------------------------------------------------------
# Internal state
# ------------------------------------------------------------------------------

_session = None
_url = None
_auth = None

# Transmission требует session id
_session_id = None


# ------------------------------------------------------------------------------
# Инициализация
# ------------------------------------------------------------------------------
def init(config):
    # Инициализация клиента Transmission.
    # - сохраняет URL
    # - сохраняет auth (или None)
    # - создаёт requests.Session

    global _session, _url, _auth, _session_id

    tcfg = config["transmission"]

    _url = tcfg["url"]

    auth = tcfg.get("auth")
    _auth = tuple(auth) if auth else None

    _session = requests.Session()

    _session_id = None

    logger.log(f"Transmission client initialized: {_url}")


# ------------------------------------------------------------------------------
# Cлужба внутренних запросов
# ------------------------------------------------------------------------------
def _rpc_call(payload, timeout=10):
    # Выполняет RPC запрос к Transmission.

    global _session_id

    headers = {}

    for _ in range(2):  # максимум 2 попытки (обновление session_id)
        if _session_id:
            headers["X-Transmission-Session-Id"] = _session_id

        r = _session.post(
            _url,
            json=payload,
            headers=headers,
            auth=_auth,
            timeout=timeout
        )

        # Transmission требует session id
        if r.status_code == 409:
            _session_id = r.headers.get("X-Transmission-Session-Id")
            continue

        r.raise_for_status()
        return r.json()

    raise RuntimeError("Transmission RPC failed (session negotiation)")


# ------------------------------------------------------------------------------
# Публичный API: список торрентов
# ------------------------------------------------------------------------------
def list_full():
    # Получает список всех торрентов.
    # Используется для проверки действительно ли торрент добавился.

    payload = {
        "method": "torrent-get",
        "arguments": {
            "fields": ["hashString", "name", "status"]
        }
    }

    data = _rpc_call(payload)

    return data.get("arguments", {}).get("torrents", [])


# ------------------------------------------------------------------------------
# Публичный API: ДОбавляем torrent / magnet ссылку
# ------------------------------------------------------------------------------
def add(magnet=None, torrent_bytes=None, max_retries=2):
    # Добавляет torrent или magnet в Transmission.
    # Возвращает:
    # - success
    # - duplicate
    # - error

    if not magnet and not torrent_bytes:
        raise ValueError("magnet or torrent_bytes required")

    # Определяем hash (для проверки magnet)
    torrent_hash = None

    if magnet:
        m = re.search(r"btih:([a-fA-F0-9]+)", magnet)
        if m:
            torrent_hash = m.group(1).lower()

    # Собираем payload
    def build_payload():
        if magnet:
            return {
                "method": "torrent-add",
                "arguments": {
                    "filename": magnet
                }
            }
        else:
            return {
                "method": "torrent-add",
                "arguments": {
                    "metainfo": base64.b64encode(torrent_bytes).decode()
                }
            }

    # Основной цикл retry
    for attempt in range(max_retries + 1):
        try:
            if attempt == 0:
                if magnet:
                    logger.log(f"Add magnet: {magnet[:60]}...")
                else:
                    logger.log(f"Add torrent file ({len(torrent_bytes)} bytes)")

            payload = build_payload()

            data = _rpc_call(payload)

            result = data.get("arguments", {})

            torrent_info = None

            if "torrent-added" in result:
                status = "success"
                torrent_info = result["torrent-added"]
            elif "torrent-duplicate" in result:
                status = "duplicate"
                torrent_info = result["torrent-duplicate"]
            else:
                raise RuntimeError("Unknown transmission response")

            torrent_name = torrent_info.get("name", "unknown")

            # Проверяем: реально ли добавился
            time.sleep(1)

            torrents = list_full()

            if torrent_hash:
                # проверка по hash (магнет)
                for t in torrents:
                    if t["hashString"].lower() == torrent_hash:
                        if status == "success":
                            logger.green(f"Added: {torrent_name}")
                        elif status == "duplicate":
                            logger.yellow(f"Already exists: {torrent_name}")
                        return status
            else:
                # для torrent файла
                if torrents:
                    if status == "success":
                        logger.green(f"Added: {torrent_name}")
                    elif status == "duplicate":
                        logger.yellow(f"Already exists: {torrent_name}")
                    return status

            # если не нашли — retry
            logger.yellow("Torrent not found after add, retrying...")

        except Exception as e:
            if attempt == max_retries:
                logger.red(f"Transmission add failed: {e}")
                return "error"

            delay = 1 + attempt
            logger.yellow(f"Transmission error (attempt {attempt+1}): {e}, retry in {delay}s")
            time.sleep(delay)

    return "error"
