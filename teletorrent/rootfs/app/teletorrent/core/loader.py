import os

from teletorrent.core.logger import get_logger

# ------------------------------------------------------------------------------
# Logger_
# ------------------------------------------------------------------------------
logger = get_logger(__name__)


# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
# /config — персистентная директория аддона (доступна пользователю)
# Здесь будет лежать языковой файл

LANG_DIR = "/config/lang"
LANG_FILE = os.path.join(LANG_DIR, "message.lang")


# ------------------------------------------------------------------------------
# Default language (используется ТОЛЬКО при init)
# ------------------------------------------------------------------------------
# Это шаблон, который создаётся:
# - при первом запуске
# - при повреждении файла
#
# Внутри документация для пользователя → НЕ УДАЛЯЕМ

DEFAULT_LANG = """
# ============================================
# Teletorrent message telegram language file
# ============================================
# Translate ONLY text AFTER ":" (right side)
# Do NOT change keys (left side)
#
# --------------------------------------------
# IMPORTANT
# --------------------------------------------
# Some messages include your Telegram name.
# In the text below it is written as:
#   {user}
#
# DO NOT change "{user}" — it must stay exactly like this.
#
# --------------------------------------------
# MULTILINE TEXT
# --------------------------------------------
# Use "\\n" to split lines.
# ============================================

[global]
no_access: 🚫 You are not authorized to use this bot
unknown_input: ⚠️ Unknown input

[start]
text: 📡 Teletorrent bot\\n\\nSend a magnet link or a .torrent file

[magnet]
added: 🧲 {user}: added
duplicate: ⚠️ {user}: already exists
error: ❌ {user}: failed

[torrent]
added: ✅ {user}: added
duplicate: ⚠️ {user}: already exists
error: ❌ {user}: failed

[errors]
invalid_file: ⚠️ {user}: not a torrent file
download_failed: ❌ {user}: failed to download file
"""


# ------------------------------------------------------------------------------
# Required structure (валидация файла)
# ------------------------------------------------------------------------------
# Если пользователь сломал файл — ловим
# и пересоздадим дефолтный

REQUIRED_KEYS = {
    "global": ["no_access", "unknown_input"],
    "start": ["text"],
    "magnet": ["added", "duplicate", "error"],
    "torrent": ["added", "duplicate", "error"],
    "errors": ["invalid_file", "download_failed"],
}


# ------------------------------------------------------------------------------
# Runtime parser (используется в worker / telegram)
# ------------------------------------------------------------------------------
def load_lang_file(path):
    """
    runtime-функция.
    - читает файл
    - парсит его в dict

    Используется в runtime (worker/telegram).
    """

    data = {}
    section = None

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            # пропускаем пустые строки и комментарии
            if not line or line.startswith("#"):
                continue

            # новая секция [section]
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                data[section] = {}
                continue

            # ключ: значение
            if ":" in line and section:
                key, value = line.split(":", 1)

                data[section][key.strip()] = (
                    value.strip()
                    .replace("\\n", "\n")  # поддержка многострочных сообщений
                )

    return data


# ------------------------------------------------------------------------------
# Validation (используется в init)
# ------------------------------------------------------------------------------
def validate_lang(data):
    """
    Проверяет структуру файла.

    Если:
    - нет секции
    - нет ключа

    → бросает исключение → файл считается повреждённым
    """

    for section, keys in REQUIRED_KEYS.items():
        if section not in data:
            raise ValueError(f"Missing section: {section}")

        for key in keys:
            if key not in data[section]:
                raise ValueError(f"Missing key: {section}.{key}")


# ------------------------------------------------------------------------------
# Init loader (используется в config.py)
# ------------------------------------------------------------------------------
def load_lang():
    """
    Init-функция.

    Используется только в config.py.

    - Создаёт файл при отсутствии
    - Валидирует
    - Если файл сломан:
        - переименовывает в .err
        - создаёт новый дефолтный

    - Не падает при повреждении файла
    - сохраняет старый файл для отладки
    """

    # ------------------------------------------------------------------
    # 1. Создание файла (если отсутствует)
    # ------------------------------------------------------------------
    os.makedirs(LANG_DIR, exist_ok=True)

    if not os.path.exists(LANG_FILE):
        with open(LANG_FILE, "w", encoding="utf-8") as f:
            f.write(DEFAULT_LANG)

        logger.log("Created default message.lang")

    # ------------------------------------------------------------------
    # 2. Проверка и валидация
    # ------------------------------------------------------------------
    try:
        data = load_lang_file(LANG_FILE)
        validate_lang(data)

        logger.green("Language validated successfully")
        return data

    # ------------------------------------------------------------------
    # 3. Авто-ремонт (если файл сломан)
    # ------------------------------------------------------------------
    except Exception as e:
        logger.red(f"Language validation failed: {e}")

        # сохраняем сломанный файл (не теряем пользовательские правки)
        err_file = LANG_FILE + ".err"
        os.replace(LANG_FILE, err_file)

        logger.yellow(f"Broken lang file renamed to {err_file}")

        # создаём новый дефолтный файл
        with open(LANG_FILE, "w", encoding="utf-8") as f:
            f.write(DEFAULT_LANG)

        logger.yellow("New default message.lang created")

        # возвращаем уже гарантированно валидный файл
        return load_lang_file(LANG_FILE)
