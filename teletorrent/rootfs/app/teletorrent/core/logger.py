import os
import sys
from datetime import datetime

# --- Levels ---
CRITICAL = 50
ERROR = 40
WARNING = 30
INFO = 20
DEBUG = 10
NOTSET = 0

LEVEL_NAMES = {
    DEBUG: "DEBUG",
    INFO: "INFO",
    WARNING: "WARNING",
    ERROR: "ERROR",
    CRITICAL: "CRITICAL",
    NOTSET: "",
}

# --- Colors ---
class Colors:
    RESET = "\033[0m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    MAGENTA = "\033[35m"
    BRIGHT_BLACK = "\033[90m"
    WHITE = "\033[97m"

LEVEL_COLORS = {
    DEBUG: Colors.BRIGHT_BLACK,
    INFO: Colors.GREEN,
    WARNING: Colors.YELLOW,
    ERROR: Colors.MAGENTA,
    CRITICAL: Colors.RED,
    NOTSET: Colors.WHITE,
}

# --- Debug flag ---
DEBUG_FLAG = os.environ.get("DEBUG_FLAG")
DEBUG_ENABLED = DEBUG_FLAG and os.path.exists(DEBUG_FLAG)

# --- Detect color support ---
def _supports_color():
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    return sys.stdout.isatty()

USE_COLOR = _supports_color()


def _timestamp():
    return datetime.now().strftime("%H:%M:%S")


def _log(level, msg):
    if level == DEBUG and not DEBUG_ENABLED:
        return

    ts = _timestamp()

    if not USE_COLOR:
        level_name = LEVEL_NAMES.get(level, "")
        if level_name:
            base = f"[{ts}] {level_name}: {msg}"
        else:
            base = f"[{ts}] {msg}"
        print(base, flush=True)
        return

    color = LEVEL_COLORS.get(level, Colors.WHITE)
    base = f"[{ts}] {msg}"
    print(f"{color}{base}{Colors.RESET}", flush=True)


# --- Logger class (совместим с logging API) ---
class SimpleLogger:
    def __init__(self, name=None):
        self.name = name

    def _fmt(self, msg):
        return f"{self.name}: {msg}" if self.name else msg

    def debug(self, msg):
        _log(DEBUG, self._fmt(msg))

    def info(self, msg):
        _log(INFO, self._fmt(msg))

    def warning(self, msg):
        _log(WARNING, self._fmt(msg))

    def error(self, msg):
        _log(ERROR, self._fmt(msg))

    def critical(self, msg):
        _log(CRITICAL, self._fmt(msg))

    def exception(self, msg):
        import traceback
        _log(ERROR, self._fmt(msg))
        traceback.print_exc()


# --- Public API ---
_loggers = {}

def get_logger(name=None):
    if name not in _loggers:
        _loggers[name] = SimpleLogger(name)
    return _loggers[name]
