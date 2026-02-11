#!/usr/bin/env python3

import sys
import time
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

BACKUP_DIR = Path("/backup")
QUEUE_FILE = Path("/tmp/backup_sync.queue")
DEBUG_FLAG = Path("/config/debug.flag")

VALID_SUFFIXES = (".tar", ".tar.gz")


# ---------------------------------------------------------
# debug helper
# ---------------------------------------------------------

def debug(msg: str):
    if DEBUG_FLAG.exists():
        print(f"[DEBUG][watcher] {msg}", flush=True)


# ---------------------------------------------------------
# handler
# ---------------------------------------------------------

class BackupHandler(FileSystemEventHandler):

    def on_created(self, event):

        if event.is_directory:
            return

        path = Path(event.src_path)

        if not path.name.endswith(VALID_SUFFIXES):
            return

        if not path.exists():
            return

        try:
            with QUEUE_FILE.open("a") as q:
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
    debug(f"watch dir={BACKUP_DIR}")
    debug(f"queue={QUEUE_FILE}")

    if not BACKUP_DIR.exists():
        print("[watcher] backup directory missing", flush=True)
        return 1

    observer = Observer()
    observer.schedule(BackupHandler(), str(BACKUP_DIR), recursive=False)
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
