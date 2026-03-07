#!/usr/bin/env python3

import os
import sys
import time
import threading
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE))

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from core.logger import (
    log_debug,
    log,
    log_green,
    log_yellow,
    log_red,
    log_blue,
)

from ha.events import emit


# =========================
# Runtime config
# =========================

DLNA_DIR = os.environ.get("DLNA_DIR")

if not DLNA_DIR:
    log_red("DLNA_DIR not defined")
    sys.exit(1)

WATCH_DIR = Path(DLNA_DIR).resolve()


VALID_SUFFIXES = (".mkv", ".srt", ".ass", ".mp4", ".avi", ".mp3", ".flac", ".jpg", ".png")

CHECK_INTERVAL = 2
STABLE_TIME = 5

# =========================
# Debounce watcher
# =========================

class DLNAWatcher:

    def __init__(self):
        self.pending = {}
        self.lock = threading.Lock()
        log_debug("DLNAWatcher initialized")

    def add_file(self, path: Path):

        if not path.exists():
            log_debug(f"ignored (not exists): {path}")
            return

        size = path.stat().st_size

        with self.lock:
            if path in self.pending:
                self.pending[path] = (size, time.time())
                log_debug(f"updated tracking: {path.name} size={size}")
                return

            self.pending[path] = (size, time.time())

        log_debug(f"tracking new file: {path.name} size={size}")

    def process(self):
        log_debug("Watcher processing thread started")

        while True:

            if not self.pending:
                time.sleep(CHECK_INTERVAL)
                continue

            time.sleep(CHECK_INTERVAL)
            now = time.time()
            to_emit = []

            with self.lock:
                for path, (last_size, last_change) in list(self.pending.items()):

                    if not path.exists():
                        log_debug(f"file disappeared: {path.name}")
                        self.pending.pop(path, None)
                        continue

                    current_size = path.stat().st_size

                    if current_size != last_size:
                        self.pending[path] = (current_size, now)
                        log_debug(f"file growing: {path.name} size={current_size}")
                        continue

                    if now - last_change >= STABLE_TIME:
                        log_debug(f"file stable: {path.name}")
                        to_emit.append(path)
                        self.pending.pop(path, None)

            for path in to_emit:
                log_green(f"added: {path.name}")
                emit("media_state", {
                    "reason": "added",
                    "file": path.name
                })
                log_debug(f"event emitted: added {path.name}")

class Handler(FileSystemEventHandler):

    def __init__(self, watcher: DLNAWatcher):
        self.watcher = watcher
        log_debug("Filesystem handler initialized")

    def on_created(self, event):
        if event.is_directory:
            return

        path = Path(event.src_path)

        if path.suffix.lower() not in VALID_SUFFIXES:
            log_debug(f"ignored (suffix): {path.name}")
            return

        log_debug(f"created event: {path.name}")
        self.watcher.add_file(path)

    def on_modified(self, event):
        if event.is_directory:
            return

        path = Path(event.src_path)

        if path.suffix.lower() not in VALID_SUFFIXES:
            return

        log_debug(f"modified event: {path.name}")
        self.watcher.add_file(path)

    def on_deleted(self, event):
        if event.is_directory:
            return

        path = Path(event.src_path)

        if path.suffix.lower() not in VALID_SUFFIXES:
            return

        log_yellow(f"removed: {path.name}")
        emit("media_state", {
            "reason": "removed",
            "file": path.name
        })
        log_debug(f"event emitted: removed {path.name}")

    def on_moved(self, event):
        if event.is_directory:
            return

        src = Path(event.src_path)
        dst = Path(event.dest_path)

        if dst.suffix.lower() not in VALID_SUFFIXES:
            log_debug(f"ignored move (suffix): {dst.name}")
            return

        log_blue(f"renamed: {src.name} -> {dst.name}")

        emit("media_state", {
            "reason": "renamed",
            "from": src.name,
            "to": dst.name
        })

        log_debug(f"event emitted: renamed {src.name} -> {dst.name}")

# =========================
# Main
# =========================

def main():

    log_green("Starting DLNA watcher")

    if not WATCH_DIR.exists():
        log_red("DLNA directory missing")
        return 1

    log_debug(f"DLNA_DIR={DLNA_DIR}")
    log_debug(f"WATCH_DIR={WATCH_DIR}")
    log_debug(f"Valid suffixes: {VALID_SUFFIXES}")
    log_debug(f"Check interval: {CHECK_INTERVAL}s")
    log_debug(f"Stable time: {STABLE_TIME}s")

    watcher = DLNAWatcher()

    observer = Observer()
    observer.schedule(Handler(watcher), str(WATCH_DIR), recursive=True)
    observer.start()

    thread = threading.Thread(target=watcher.process, daemon=True)
    thread.start()

    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        log_yellow("Watcher interrupted")
    finally:
        log_blue("Stopping watcher")
        observer.stop()
        observer.join()
        log_green("Watcher stopped")


if __name__ == "__main__":
    sys.exit(main())
