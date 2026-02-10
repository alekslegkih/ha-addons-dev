#!/usr/bin/env python3

import time
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

BACKUP_DIR = Path("/backup")
QUEUE_FILE = Path("/tmp/backup_sync.queue")


class BackupHandler(FileSystemEventHandler):

    def on_created(self, event):
        if event.is_directory:
            return

        path = Path(event.src_path)

        # только архивы
        if not (path.name.endswith(".tar") or path.name.endswith(".tar.gz")):
            return

        # просто пишем в очередь — ВСЁ
        try:
            with QUEUE_FILE.open("a") as f:
                f.write(str(path) + "\n")
        except Exception:
            # watcher не лечит ошибки
            # если очередь сломалась — пусть процесс умрёт
            raise


def main():

    # если нет источника — просто выходим
    # run/s6 решит что делать
    if not BACKUP_DIR.exists():
        return 1

    observer = Observer()
    observer.schedule(BackupHandler(), str(BACKUP_DIR), recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(3600)   # максимально редкий wakeup
    finally:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    main()
