#!/usr/bin/env python3

import sys
from pathlib import Path

# ---------------------------------------------------------
# добавить корень проекта в sys.path
# ---------------------------------------------------------

BASE = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE))

# ---------------------------------------------------------
# обычные импорты
# ---------------------------------------------------------

import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from ha.events import emit
from core import config   # <-- ВОТ ОНО


# ---------------------------------------------------------
# debug helper
# ---------------------------------------------------------

def debug(msg: str):
    if config.DEBUG_FLAG.exists():
        print(f"[DEBUG][watcher] {msg}", flush=True)


# ---------------------------------------------------------
# handler
# ---------------------------------------------------------

class BackupHandler(FileSystemEventHandler):

    def on_created(self, event):

        if event.is_directory:
            return

        path = Path(event.src_path)

        if not path.name.endswith(config.VALID_SUFFIXES):
            return

        if not path.exists():
            return

        try:
            with config.QUEUE_FILE.open("a") as q:
                q.write(str(path) + "\n")

            debug(f"queued: {path.name}")

        except Exception as e:
            print(f"[watcher] fatal: {e}", flush=True)
            sys.exit(1)


# ---------------------------------------------------------
# main
# ---------------------------------------------------------

def main():

    debug("boot")
    debug(f"watch dir={config.BACKUP_DIR}")
    debug(f"queue={config.QUEUE_FILE}")

    if not config.BACKUP_DIR.exists():
        print("[watcher] backup directory missing", flush=True)
        return 1

    observer = Observer()
    observer.schedule(BackupHandler(), str(config.BACKUP_DIR), recursive=False)
    observer.start()

    debug("started")

    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        pass
    finally:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    sys.exit(main())
