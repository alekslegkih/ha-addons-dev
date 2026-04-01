import logging
import sys

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BRIGHT_BLACK = '\033[90m'

class ColoredFormatter(logging.Formatter):
    LEVEL_COLORS = {
        logging.DEBUG: Colors.BRIGHT_BLACK,
        logging.INFO: Colors.GREEN,
        logging.WARNING: Colors.YELLOW,
        logging.ERROR: Colors.RED,
        logging.CRITICAL: Colors.RED,
    }

    def format(self, record):
        timestamp = self.formatTime(record, self.datefmt)
        levelname = record.levelname
        message = record.getMessage()

        color = self.LEVEL_COLORS.get(record.levelno, Colors.RESET)

        return f"[{timestamp}] {levelname}: {color}{message}{Colors.RESET}"

def setup_logger(name=None, level=logging.INFO):
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)
    handler.setFormatter(ColoredFormatter(datefmt='%H:%M:%S'))

    logger.addHandler(handler)
    return logger
