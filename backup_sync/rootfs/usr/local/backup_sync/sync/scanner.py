#!/usr/bin/env python3

import os
import sys
from pathlib import Path

BACKUP_DIR = Path("/backup")
QUEUE_FILE = Path("/tmp/backup_sync.queue")
DEBUG_FLAG = Path("/config/debug.flag")

VALID_PATTERNS = ("*.tar", "*.tar.gz")


# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------

def debug(msg: str):
    if DEBUG_FLAG.exists():
        print(f"[DEBUG][scanner] {msg}", flush=True)


def list_backups(path: Path):
    files = []
    for pattern in VALID_PATTERNS:
        files.extend(path.glob(pattern))
    return files


# ---------------------------------------------------------
# main
# ---------------------------------------------------------

def main():

    mount_point = os.getenv("MOUNT_POINT")

    if not mount_point:
        print("Initial scan skipped: MOUNT_POINT not set")
        return 0

    target_dir = Path("/media") / mount_point

    debug(f"source={BACKUP_DIR}")
    debug(f"target={target_dir}")
    debug(f"queue={QUEUE_FILE}")

    if not BACKUP_DIR.exists():
        debug("source dir missing")
        return 1

    if not target_dir.exists():
        debug("target dir missing")
        return 1

    # -----------------------------------------------------
    # collect
    # -----------------------------------------------------

    backups = list_backups(BACKUP_DIR)
    backups.sort(key=lambda p: p.stat().st_mtime)

    existing = {f.name for f in list_backups(target_dir)}

    found = len(backups)
    already = 0
    queued = 0

    # -----------------------------------------------------
    # enqueue
    # -----------------------------------------------------

    with QUEUE_FILE.open("a") as q:
        for b in backups:

            if b.name in existing:
                already += 1
                debug(f"skip existing: {b.name}")
                continue

            q.write(str(b) + "\n")
            queued += 1
            debug(f"queued: {b.name}")

    # -----------------------------------------------------
    # pretty summary (user-facing)
    # -----------------------------------------------------

    print("Initial scan:")
    print(f"  Found:     {found}")
    print(f"  Existing:  {already}")
    print(f"  Queued:    {queued}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
