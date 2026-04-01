import os
import json
import sys

from teletorrent.core.logger import get_logger
from teletorrent.core.loader import load_lang
from datetime import datetime

# ------------------------------------------------------------------------------
# Logger_
# ------------------------------------------------------------------------------
logger = get_logger(__name__)


# ------------------------------------------------------------------------------
# Paths (все пути централизованы здесь)
# ------------------------------------------------------------------------------

# Входной конфиг от Home Assistant
OPTIONS_FILE = "/data/options.json"

# Стандартный путь s6-overlay для env переменных
# Каждая переменная = отдельный файл
ENV_DIR = "/run/s6/container_environment"

# Путь до языкового файла (его создаёт loader)
LANG_FILE = "/config/lang/message.lang"

# Путь для хранения offset Telegram (используется в runtime)
OFFSET_FILE = "/config/offset"


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

def fail(msg):
    """
    Фатальная ошибка:
    - логируем
    - завершаем процесс с кодом 1

    Важно:
    s6 one-shot сервис НЕ перезапускается,
    поэтому exit(1) = контейнер не поднимется
    """
    logger.red(msg)
    sys.exit(1)


def write_env(name, value):
    """
    Запись переменной окружения в s6 формате:
    /run/s6/container_environment/<NAME>

    Почему так:
    - не нужно экранировать JSON
    - стандартный способ для s6-overlay
    - автоматически попадёт в os.environ в runtime

    value должен быть строкой!
    """
    path = os.path.join(ENV_DIR, name)

    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(value)
    except Exception as e:
        fail(f"Failed to write env {name}: {e}")


# ------------------------------------------------------------------------------
# Load options.json
# ------------------------------------------------------------------------------

def load_options():
    """
    Читаем основной конфиг аддона.

    Это сырой конфиг от Home Assistant.
    Здесь мы НЕ используем его напрямую,
    а только как источник для нормализации.
    """
    if not os.path.exists(OPTIONS_FILE):
        fail("options.json not found")

    try:
        with open(OPTIONS_FILE) as f:
            return json.load(f)
    except Exception as e:
        fail(f"Failed to read options.json: {e}")


# ------------------------------------------------------------------------------
# Normalize: Telegram
# ------------------------------------------------------------------------------

def build_telegram(cfg):
    """
    Подготавливаем Telegram конфиг для runtime.

    Что делаем:
    - проверяем token
    - преобразуем список пользователей в dict

    Было:
        [
            {"u_id": 123, "u_name": "Ivan"}
        ]

    Стало:
        {
            "123": "Ivan"
        }

    Почему:
    - быстрее доступ
    - проще проверка авторизации
    """

    token = cfg.get("token")
    if not token:
        fail("config: 'token' is required")

    raw_users = cfg.get("user_ids", [])

    users = []

    for u in raw_users:
        if not isinstance(u, dict):
            continue

        uid = u.get("u_id")
        name = u.get("u_name", str(uid))

        try:
            uid = int(uid)
        except (TypeError, ValueError):
            continue

        users.append({
            "id": uid,
            "name": name
        })

    # если список пуст — не ошибка, предупреждение
    if not users:
        logger.yellow("No authorized users configured")

    return {
        "token": token,
        "users": users
    }


# ------------------------------------------------------------------------------
# Normalize: Transmission
# ------------------------------------------------------------------------------

def build_transmission(cfg):
    """
    Подготавливаем конфиг для Transmission.

    Что делаем:
    - собираем полный RPC URL
    - формируем auth (или None)
    - задаём watch_folder
    """

    tcfg = cfg.get("transmission", {})

    host = tcfg.get("host")
    if not host:
        fail("transmission: 'host' is required")

    port = tcfg.get("port", 9091)

    # сразу формируем конечный URL
    url = f"http://{host}:{port}/transmission/rpc"

    username = tcfg.get("username")
    password = tcfg.get("password")

    # если нет авторизации — просто None
    auth = None
    if username and password:
        auth = [username, password]

    # дефолтная папка для fallback
    watch_folder = tcfg.get("watch_folder", "/share/watch")

    return {
        "url": url,
        "auth": auth,
        "watch_folder": watch_folder
    }


# ------------------------------------------------------------------------------
# Normalize: Proxy
# ------------------------------------------------------------------------------

def build_proxy(cfg):
    """
    Подготавливаем proxy конфиг.

    Логика:
    - если disabled → игнорируем всё
    - если enabled → собираем URL
    - если что-то сломано → отключаем proxy

    НЕ падаем:
    proxy — опциональная вещь
    """

    pcfg = cfg.get("proxy", {})

    enabled = pcfg.get("enabled", False)

    if not enabled:
        return {
            "enabled": False,
            "url": None
        }

    ptype = pcfg.get("type")
    host = pcfg.get("host")
    port = pcfg.get("port")

    # проверка типа
    if not ptype or ptype not in ("socks", "http"):
        logger.yellow("proxy enabled but invalid type → disabling")
        return {"enabled": False, "url": None}

    # проверка host/port
    if not host or not port:
        logger.yellow("proxy enabled but host/port missing → disabling")
        return {"enabled": False, "url": None}

    scheme = "socks5h" if ptype == "socks" else "http"

    username = pcfg.get("username")
    password = pcfg.get("password")

    # собираем URL
    if username and password:
        url = f"{scheme}://{username}:{password}@{host}:{port}"
    else:
        url = f"{scheme}://{host}:{port}"

    return {
        "enabled": True,
        "url": url
    }


# ------------------------------------------------------------------------------
# Main (entrypoint)
# ------------------------------------------------------------------------------

def main():
    """
    Главная функция init-конфига.

    Последовательность:
    1. читаем options.json
    2. нормализуем конфиг
    3. инициализируем lang (через loader)
    4. пишем ENV
    5. завершаемся

    Важно:
    Этот процесс выполняется ОДИН раз при старте контейнера
    """
    ADDON_VERSION = os.environ.get("BUILD_VERSION", "dev")

    logger.blue("========================================")
    logger.green("=== TeleTorrent ===")
    logger.green(f"=== Version:  {ADDON_VERSION} ===")
    logger.green(f"Starting at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.blue("========================================")

    logger.log("Config init started...")

    # ------------------------------------------------------------------
    # 1. Загружаем сырой конфиг
    # ------------------------------------------------------------------
    cfg = load_options()

    # ------------------------------------------------------------------
    # 2. Нормализуем (готовим runtime-конфиг)
    # ------------------------------------------------------------------
    telegram = build_telegram(cfg)
    transmission = build_transmission(cfg)
    proxy = build_proxy(cfg)

    runtime_cfg = {
        "telegram": telegram,
        "transmission": transmission,
        "proxy": proxy
    }

    # ------------------------------------------------------------------
    # 3. Инициализация языкового файла
    # ------------------------------------------------------------------
    # loader:
    # - создаёт файл если нет
    # - валидирует
    # - чинит если сломан
    try:
        load_lang()
    except Exception as e:
        fail(f"Language init failed: {e}")

    # ------------------------------------------------------------------
    # 4. Подготавливаем ENV директорию
    # ------------------------------------------------------------------
    os.makedirs(ENV_DIR, exist_ok=True)

    # ------------------------------------------------------------------
    # 5. Записываем переменные окружения
    # ------------------------------------------------------------------

    # Основной конфиг (единым JSON)
    write_env("TT_CONFIG_JSON", json.dumps(runtime_cfg))

    # Пути
    write_env("TT_LANG_FILE", LANG_FILE)
    write_env("TT_OFFSET_FILE", OFFSET_FILE)

    logger.green("Config init completed successfully")

    # ------------------------------------------------------------------
    # 6. Завершение
    # ------------------------------------------------------------------
    sys.exit(0)


# ------------------------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------------------------

if __name__ == "__main__":
    main()
