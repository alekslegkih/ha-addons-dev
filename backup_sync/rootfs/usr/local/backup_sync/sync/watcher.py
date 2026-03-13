#!/usr/bin/env python3

import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE))

# ---------------------------------------------------------
#
# ---------------------------------------------------------

import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from core.logger import (
    log_debug,
    log,
    log_green,
    log_yellow,
    log_red,
)

env = {}

env_path = Path("/run/backup_sync/runtime.env")

if not env_path.exists():
    log_red(f"runtime.env missing", flush=True)
    sys.exit(1)

with env_path.open() as f:
    for line in f:
        line = line.strip()

        if not line or "=" not in line:
            continue

        k, v = line.split("=", 1)
        env[k] = v.strip().strip("'").strip('"')

SOURCE_DIR = Path(env.get("SOURCE_DIR", ""))
DEBUG_FLAG = Path(env.get("DEBUG_FLAG", ""))
QUEUE_FILE = Path(env.get("QUEUE_FILE", ""))

# ---------------------------------------------------------
# handler
# ---------------------------------------------------------
VALID_SUFFIXES = (".tar", ".tar.gz")

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

            log_debug(f"queued: {path.name}")

        except Exception as e:
            print(f"[watcher] fatal: {e}", flush=True)
            sys.exit(1)


# ---------------------------------------------------------
# main
# ---------------------------------------------------------

def main():

    log_debug("boot")
    log_debug(f"watch dir={SOURCE_DIR}")
    log_debug(f"queue={QUEUE_FILE}")

    if not SOURCE_DIR.exists():
        print("[watcher] backup directory missing", flush=True)
        return 1

    observer = Observer()
    observer.schedule(BackupHandler(), str(SOURCE_DIR), recursive=False)
    observer.start()

    log_debug("started")

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
