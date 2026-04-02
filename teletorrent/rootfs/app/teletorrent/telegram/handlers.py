import os

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

def t(lang, section, key, **kwargs):
    """
    Удобный доступ к lang.
    """
    text = lang.get(section, {}).get(key, key)
    return text.format(**kwargs)


# ------------------------------------------------------------------------------
# Обработчик текста
# ------------------------------------------------------------------------------
def handle_text(ctx, msg, user_name):
    # Обработка текстовых сообщений.

    send = ctx["send"]
    transmission = ctx["transmission"]
    emit = ctx["emit"]
    lang = ctx["lang"]

    chat_id = msg["chat"]["id"]
    text = msg.get("text", "").strip()

    # /start и /help
    if text in ("/start", "/help"):
        send(chat_id, t(lang, "start", "text"))
        return True

    # magnet
    if not text.startswith("magnet:?xt=urn:btih:"):
        return False

    result = transmission(magnet=text)

    status_map = {
        "success": ("magnet", "added"),
        "duplicate": ("magnet", "duplicate"),
        "error": ("magnet", "error"),
    }

    section, key = status_map.get(result, ("magnet", "error"))

    send(chat_id, t(lang, section, key, user=user_name))

    emit("event", {
        "reason": f"magnet_{result}",
        "user_name": user_name
    })

    return True


# ------------------------------------------------------------------------------
# Обработчик torrent
# ------------------------------------------------------------------------------
def handle_document(ctx, msg, user_name):
    # Обработка .torrent файлов.

    send = ctx["send"]
    transmission = ctx["transmission"]
    emit = ctx["emit"]
    lang = ctx["lang"]
    download_file = ctx["download_file"]
    watch_folder = ctx["watch_folder"]

    chat_id = msg["chat"]["id"]

    doc = msg["document"]
    filename = doc.get("file_name", "")

    # Проверка расширения
    if not filename.endswith(".torrent"):
        send(chat_id, t(lang, "errors", "invalid_file", user=user_name))

        emit("event", {
            "reason": "invalid_input",
            "type": "file",
            "name": filename,
            "user_name": user_name
        })

        return

    file_id = doc["file_id"]

    # Скачивание файла через API слой
    try:
        file_data = download_file(file_id)
    except Exception:
        send(chat_id, t(lang, "errors", "download_failed", user=user_name))
        return

    # Передача в transmission
    result = transmission(torrent_bytes=file_data)

    status_map = {
        "success": ("torrent", "added"),
        "duplicate": ("torrent", "duplicate"),
        "error": ("torrent", "error"),
    }

    section, key = status_map.get(result, ("torrent", "error"))

    send(chat_id, t(lang, section, key, user=user_name))

    emit("event", {
        "reason": f"torrent_{result}",
        "name": filename,
        "user_name": user_name
    })

    # Fallback (если transmission не принял)
    if result == "error":
        try:
            os.makedirs(watch_folder, exist_ok=True)

            save_path = os.path.join(watch_folder, filename)

            with open(save_path, "wb") as f:
                f.write(file_data)

            send(chat_id, f"⚠️ {user_name}: added via fallback")

            emit("event", {
                "reason": "torrent_error",
                "name": filename,
                "user_name": user_name,
                "add": "fallback"
            })

        except Exception:
            # fallback тоже может упасть — не критично
            pass
