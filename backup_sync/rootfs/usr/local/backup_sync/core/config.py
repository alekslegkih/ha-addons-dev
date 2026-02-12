import os
from pathlib import Path

# ----------------------------
# static paths
# ----------------------------

BASE_DIR = Path(os.environ["BASE_DIR"])
BACKUP_DIR = Path(os.environ["BACKUP_DIR"])
QUEUE_FILE = Path(os.environ["QUEUE_FILE"])
DEBUG_FLAG = Path(os.environ["DEBUG_FLAG"])
TARGET_ROOT = Path(os.environ["TARGET_ROOT"])

# ----------------------------
# runtime config
# ----------------------------

MOUNT_POINT = os.environ.get("MOUNT_POINT", "")
USB_DEVICE = os.environ.get("USB_DEVICE", "")
MAX_COPIES = int(os.environ.get("MAX_COPIES", "0"))
SYNC_EXIST_START = os.environ.get("SYNC_EXIST_START") == "true"

# ----------------------------
# VALID_ config 
# ----------------------------
VALID_SUFFIXES = (".tar", ".tar.gz")
VALID_PATTERNS = ("*.tar", "*.tar.gz")

