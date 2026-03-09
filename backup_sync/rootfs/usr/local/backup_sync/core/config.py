import os
from pathlib import Path

# ----------------------------
# static paths
# ----------------------------

BASE_DIR = Path(os.environ["BASE_DIR"])
SOURCE_DIR = Path(os.environ["SOURCE_DIR"])
QUEUE_FILE = Path(os.environ["QUEUE_FILE"])
DEBUG_FLAG = Path(os.environ["DEBUG_FLAG"])
TARGET_ROOT = Path(os.environ["TARGET_ROOT"])

# ----------------------------
# runtime config
# ----------------------------

TARGET_DIR = os.environ.get("TARGET_DIR", "")
DEVICE = os.environ.get("DEVICE", "")
MAX_COPIES = int(os.environ.get("MAX_COPIES", "0"))
SYNC_EXIST_START = os.environ.get("SYNC_EXIST_START") == "true"

# ----------------------------
# target path config
# ----------------------------

TARGET_PATH = None
if DEVICE and TARGET_DIR:
    TARGET_PATH = TARGET_ROOT / DEVICE / TARGET_DIR

# ----------------------------
# VALID_ config
# ----------------------------
VALID_SUFFIXES = (".tar", ".tar.gz")
VALID_PATTERNS = ("*.tar", "*.tar.gz")

