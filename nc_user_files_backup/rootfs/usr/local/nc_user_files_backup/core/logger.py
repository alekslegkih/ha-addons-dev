import os

# ANSI color codes for terminal output
RESET   = "\033[0m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
RED     = "\033[31m"
BLUE    = "\033[34m"
MAGENTA = "\033[35m"

# Debug mode flag
# Enabled if DEBUG_FLAG env variable points to an existing file
DEBUG_FLAG = os.environ.get("DEBUG_FLAG")
DEBUG = DEBUG_FLAG and os.path.exists(DEBUG_FLAG)


# Internal print helper with color support
# Arguments:
#   color - ANSI color code
#   msg   - message to print
def _print(color, msg):
    print(f"{color}{msg}{RESET}", flush=True)


# Default log (no color)
def log(msg):
    print(msg, flush=True)


# Colored log helpers
def log_green(msg):
    _print(GREEN, msg)


def log_yellow(msg):
    _print(YELLOW, msg)


def log_red(msg):
    _print(RED, msg)


def log_blue(msg):
    _print(BLUE, msg)


def log_magenta(msg):
    _print(MAGENTA, msg)


# Debug log (magenta, prefixed)
# Only prints if DEBUG flag is enabled
def log_debug(msg):
    if DEBUG:
        _print(MAGENTA, f"[DEBUG] {msg}")

