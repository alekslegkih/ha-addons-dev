import time
import requests

from teletorrent.core.logger import get_logger

logger = get_logger(__name__)

# ------------------------------------------------------------------------------
# Internal state
# ------------------------------------------------------------------------------

_session = None
_token = None

# rate limit состояние
_last_send_time = 0.0
_user_last_send = {}


# ------------------------------------------------------------------------------
# Init
# ------------------------------------------------------------------------------
def init(config):
    # Инициализация Telegram API слоя.
    # - сохраняет token
    # - создаёт requests.Session
    # - настраивает proxy (если есть)
    # - сбрасывает rate-limit состояние

    global _session, _token, _last_send_time, _user_last_send

    _token = config["telegram"]["token"]

    # создаём session
    _session = requests.Session()

    # proxy
    proxy_cfg = config.get("proxy", {})

    if proxy_cfg.get("enabled") and proxy_cfg.get("url"):
        _session.proxies = {
            "http": proxy_cfg["url"],
            "https": proxy_cfg["url"],
        }

        logger.log(f"Proxy enabled: {_mask_proxy(proxy_cfg['url'])}")

    # сбрасываем лимиты
    _last_send_time = 0.0
    _user_last_send = {}

    logger.log("Telegram API initialized")

def _mask_proxy(url):
    # Маскирует пароль в proxy URL:

    try:
        if "@" not in url:
            return url

        creds, rest = url.split("@", 1)

        if ":" in creds:
            scheme_and_user, _ = creds.rsplit(":", 1)
            return f"{scheme_and_user}:***@{rest}"

        return url
    except Exception:
        return url

# ------------------------------------------------------------------------------
# Low-level API
# ------------------------------------------------------------------------------
def telegram_api(method, params=None, timeout=35):
    # Низкоуровневый вызов Telegram API.
    # - делает POST
    # - проверяет HTTP статус
    # - проверяет поле ok
    # - возвращает JSON

    if _session is None or _token is None:
        raise RuntimeError("Telegram API not initialized")

    url = f"https://api.telegram.org/bot{_token}/{method}"

    r = _session.post(url, json=params or {}, timeout=timeout)
    r.raise_for_status()

    data = r.json()

    if not data.get("ok"):
        raise RuntimeError(f"Telegram API error: {data}")

    return data


# ------------------------------------------------------------------------------
# Rate limit helpers
# ------------------------------------------------------------------------------
def _wait_global_limit():
    # Глобальный лимит (~50ms между любыми сообщениями)

    global _last_send_time

    now = time.time()
    delta = now - _last_send_time

    min_interval = 0.05

    if delta < min_interval:
        time.sleep(min_interval - delta)


def _wait_user_limit(chat_id):
   # Лимит на пользователя (~500ms)

    global _user_last_send

    now = time.time()
    last = _user_last_send.get(chat_id, 0)

    min_interval = 0.5

    delta = now - last

    if delta < min_interval:
        time.sleep(min_interval - delta)


# ------------------------------------------------------------------------------
# High-level API
# ------------------------------------------------------------------------------
def send_message(chat_id, text, max_retries=2):
    # Отправка сообщения в Telegram.
    # - соблюдает rate limit (глобальный + per user)
    # - делает retry при ошибках
    # - логирует ошибки
    # - логирует успех (debug)

    global _last_send_time, _user_last_send

    for attempt in range(max_retries + 1):
        try:
            # Cоблюдаем лимиты ПЕРЕД каждой попыткой
            _wait_global_limit()
            _wait_user_limit(chat_id)

            # Отправка
            telegram_api("sendMessage", {
                "chat_id": chat_id,
                "text": text
            })

            # При успехе обновляем тайминги
            now = time.time()
            _last_send_time = now
            _user_last_send[chat_id] = now

            log.magenta(f"Message sent to {chat_id}")

            return True

        except Exception as e:
            # если это последняя попытка — логируем и выходим
            if attempt == max_retries:
                logger.yellow(f"send_message failed after retries: {e}")
                return False

            # retry с задержкой
            delay = 0.5 * (attempt + 1)
            logger.yellow(f"send_message error (attempt {attempt+1}): {e}, retry in {delay}s")

            time.sleep(delay)


# ------------------------------------------------------------------------------
# File API (Telegram-specific)
# ------------------------------------------------------------------------------

def download_file(file_id, timeout=35):
    # Скачивает файл из Telegram по file_id.
    # - вызывает getFile → получает file_path
    # - скачивает файл по file_path
    # - возвращает bytes

    if _session is None or _token is None:
        raise RuntimeError("Telegram API not initialized")

    # 1. Получаем путь к файлу
    data = telegram_api("getFile", {"file_id": file_id})

    file_path = data["result"]["file_path"]

    # 2. Формируем URL
    file_url = f"https://api.telegram.org/file/bot{_token}/{file_path}"

    # 3. Скачиваем файл
    r = _session.get(file_url, timeout=timeout)
    r.raise_for_status()

    return r.content
