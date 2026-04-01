import os
import json
import time
import requests

import sys

from teletorrent.core.logger import get_logger
from teletorrent.core.loader import load_lang_file

from teletorrent.telegram import api
from teletorrent.telegram.handlers import handle_text, handle_document
from teletorrent.telegram.offset import get_offset, set_offset

from teletorrent.transmission import client as transmission
from teletorrent.ha.events import emit


# ------------------------------------------------------------------------------
# Logger_
# ------------------------------------------------------------------------------
log = get_logger(__name__)

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
def main():
    """
    Основной процесс (long-running worker).

    Делает:
    - загружает config из ENV
    - загружает lang файл
    - инициализирует модули
    - запускает polling loop (getUpdates)
    """
    # ------------------------------------------------------------------
    # 1. Загрузка config из ENV
    # ------------------------------------------------------------------
    try:
        cfg = json.loads(os.environ["TT_CONFIG_JSON"])
    except Exception as e:
        log.red(f"Failed to load config from ENV: {e}")
        exit(1)

    # ------------------------------------------------------------------
    # 2. Загрузка lang
    # ------------------------------------------------------------------
    try:
        lang_path = os.environ["TT_LANG_FILE"]
        lang = load_lang_file(lang_path)
    except Exception as e:
        log.red(f"Failed to load lang file: {e}")
        exit(1)

    # ------------------------------------------------------------------
    # 3. Offset файл
    # ------------------------------------------------------------------
    offset_path = os.environ.get("TT_OFFSET_FILE", "/config/offset")

    # ------------------------------------------------------------------
    # 4. Инициализация модулей
    # ------------------------------------------------------------------
    api.init(cfg)
    transmission.init(cfg)

    # ------------------------------------------------------------------
    # 5. Подготовка пользователей
    # ------------------------------------------------------------------
    raw_users = cfg.get("telegram", {}).get("users", [])

    users = {
        u["id"]: u["name"]
        for u in raw_users
    }

    if not users:
        log.yellow("User list is empty — no one is authorized")

    # ------------------------------------------------------------------
    # 6. Сборка ctx (контекст для handlers)
    # ------------------------------------------------------------------
    ctx = {
        "send": api.send_message,
        "download_file": api.download_file,
        "transmission": transmission.add,
        "emit": emit,
        "lang": lang,
        "watch_folder": cfg["transmission"].get("watch_folder", "/share/watch"),
    }

    log.green("Worker started")

    # ------------------------------------------------------------------
    # 7. Runtime состояние
    # ------------------------------------------------------------------
    processed_updates = set()
    error_count = 0

    # ------------------------------------------------------------------
    # 8. Main loop
    # ------------------------------------------------------------------
    while True:
        try:
            offset = get_offset(offset_path)

            # ----------------------------------------------------------
            # Запрос обновлений у Telegram
            # ----------------------------------------------------------
            updates = api.telegram_api(
                "getUpdates",
                {
                    "offset": offset + 1,
                    "timeout": 30
                },
                timeout=35
            )

            error_count = 0

            last_update_id = None

            # ----------------------------------------------------------
            # Обработка обновлений
            # ----------------------------------------------------------
            for update in updates.get("result", []):
                update_id = update["update_id"]

                # защита от дублей
                if update_id in processed_updates:
                    continue
                processed_updates.add(update_id)

                if "message" not in update:
                    continue

                msg = update["message"]

                chat_id = msg.get("chat", {}).get("id")
                user_id = msg.get("from", {}).get("id")

                if not chat_id or not user_id:
                    continue

                last_update_id = update_id

                text = msg.get("text", "").strip()

                # ------------------------------------------------------
                # Проверка доступа
                # ------------------------------------------------------
                if user_id not in users:
                    if text in ("/start", "/help"):
                        api.send_message(
                            chat_id,
                            ctx["lang"]["global"]["no_access"]
                        )
                    else:
                        log.yellow(f"Unauthorized user: {user_id}")
                    continue

                user_name = users.get(user_id, str(user_id))

                # ------------------------------------------------------
                # Обработка сообщения
                # ------------------------------------------------------
                try:
                    if "document" in msg:
                        handle_document(ctx, msg, user_name)

                    elif "text" in msg:
                        if not handle_text(ctx, msg, user_name):
                            api.send_message(
                                chat_id,
                                ctx["lang"]["global"]["unknown_input"]
                            )

                except Exception as e:
                    log.yellow(f"Handler error: {e}")
                    time.sleep(1)

            # ----------------------------------------------------------
            # Чистим кэш обработанных update
            # ----------------------------------------------------------
            if len(processed_updates) > 10000:
                processed_updates.clear()

            # ----------------------------------------------------------
            # Сохраняем offset
            # ----------------------------------------------------------
            if last_update_id is not None:
                set_offset(offset_path, last_update_id)

        # --------------------------------------------------------------
        # Таймаут Telegram (нормальная ситуация)
        # --------------------------------------------------------------
        except requests.exceptions.ReadTimeout:
            time.sleep(1)
            continue

        # --------------------------------------------------------------
        # Общие ошибки
        # --------------------------------------------------------------
        except Exception as e:
            log.yellow(f"Worker error: {e}")

            error_count += 1

            sleep_time = min(error_count, 10)
            log.yellow(f"Backoff sleep: {sleep_time}s")

            time.sleep(sleep_time)

            if error_count >= 10:
                log.red("Too many errors, exiting")
                exit(1)


# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    main()
