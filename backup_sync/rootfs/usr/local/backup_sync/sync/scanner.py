#!/usr/bin/env python3

import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE))

import os
from ha.events import emit
from core import config   # <-- include config.h


# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------

def debug(msg: str):
    if config.DEBUG_FLAG.exists():
        print(f"[DEBUG][scanner] {msg}", flush=True)


def list_backups(path: Path):
    files = []
    for pattern in config.VALID_PATTERNS:
        files.extend(path.glob(pattern))
    return files


# ---------------------------------------------------------
# main
# ---------------------------------------------------------

def main():

    mount_point = config.MOUNT_POINT   # <-- берём из config

    if not mount_point:
        print("Initial scan skipped: MOUNT_POINT not set")
        return 0

    target_dir = config.TARGET_ROOT / mount_point

    debug(f"source={config.BACKUP_DIR}")
    debug(f"target={target_dir}")
    debug(f"queue={config.QUEUE_FILE}")

    if not config.BACKUP_DIR.exists():
        debug("source dir missing")
        return 1

    if not target_dir.exists():
        debug("target dir missing")
        return 1

    # -----------------------------------------------------
    # collect
    # -----------------------------------------------------

    backups = list_backups(config.BACKUP_DIR)
    backups.sort(key=lambda p: p.stat().st_mtime)

    existing = {f.name for f in list_backups(target_dir)}

    found = len(backups)
    already = 0
    queued = 0

    # -----------------------------------------------------
    # enqueue
    # -----------------------------------------------------

    with config.QUEUE_FILE.open("a") as q:
        for b in backups:

            if b.name in existing:
                already += 1
                debug(f"skip existing: {b.name}")
                continue

            q.write(str(b) + "\n")
            queued += 1
            debug(f"queued: {b.name}")

    # -----------------------------------------------------

    print("Initial scan:")
    print(f"  Found:     {found}")
    print(f"  Existing:  {already}")
    print(f"  Queued:    {queued}")

    emit("initial_scan_completed", {
        "found": found,
        "existing": already,
        "queued": queued
    })

    return 0


if __name__ == "__main__":
    sys.exit(main())
