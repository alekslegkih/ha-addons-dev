#!/usr/bin/env python3

import os
from pathlib import Path


BACKUP_DIR = Path("/backup")
QUEUE_FILE = Path("/tmp/backup_sync.queue")

VALID_SUFFIXES = (".tar", ".tar.gz")


def list_backups(path: Path):
    files = []
    for ext in VALID_SUFFIXES:
        files.extend(path.glob(ext))
    return files


def main():

    mount_point = os.getenv("MOUNT_POINT", "backups")
    target_dir = Path("/media") / mount_point

    # -----------------------------------------------------
    # Collect
    # -----------------------------------------------------

    backups = list_backups(BACKUP_DIR)
    backups.sort(key=lambda p: p.stat().st_mtime)

    existing = {f.name for f in list_backups(target_dir)}

    # -----------------------------------------------------
    # Enqueue missing
    # -----------------------------------------------------

    with QUEUE_FILE.open("a") as q:
        for b in backups:
            if b.name not in existing:
                q.write(str(b) + "\n")


if __name__ == "__main__":
    main()
