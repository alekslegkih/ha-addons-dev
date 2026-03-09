#!/usr/bin/env python3

import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE))

import os
from ha.events import emit

env = {}

env_path = Path("/run/backup_sync/runtime.env")

if not env_path.exists():
    print("[watcher] runtime.env missing", flush=True)
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
TARGET_PATH = Path(env.get("TARGET_PATH", ""))

# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------


def debug(msg: str):
    if DEBUG_FLAG.exists():
        print(f"[DEBUG][scanner] {msg}", flush=True)



VALID_PATTERNS = ("*.tar", "*.tar.gz")

def list_backups(path: Path):
    files = []
    for pattern in VALID_PATTERNS:
        files.extend(path.glob(pattern))
    return files

# ---------------------------------------------------------
# main
# ---------------------------------------------------------

def main():

    debug(f"source={SOURCE_DIR}")
    debug(f"target={TARGET_PATH}")
    debug(f"queue={QUEUE_FILE}")


    if not SOURCE_DIR.exists():
        debug("source dir missing")
        return 1

    if not TARGET_PATH.exists():
        debug("target dir missing")
        return 1

    # -----------------------------------------------------
    # collect
    # -----------------------------------------------------

    backups = list_backups(SOURCE_DIR)
    backups.sort(key=lambda p: p.stat().st_mtime)

    existing = {f.name for f in list_backups(TARGET_PATH)}

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
