import logging
import sys

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    WHITE = '\033[97m'
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
        # Форматируем время
        timestamp = self.formatTime(record, self.datefmt)
        levelname = record.levelname

        # Цветное сообщение
        color = self.LEVEL_COLORS.get(record.levelno, Colors.WHITE)
        colored_message = f"{color}{record.getMessage()}{Colors.RESET}"

        # Формат: [HH:MM:SS] LEVEL: colored_message
        return f"[{timestamp}] {levelname}: {colored_message}"

def setup_logger(name=None, level=logging.INFO):
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Очищаем старые handlers если есть
    logger.handlers.clear()

    # Создаем handler для вывода в консоль
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)

    # Настраиваем форматтер
    formatter = ColoredFormatter(datefmt='%H:%M:%S')
    handler.setFormatter(formatter)

    logger.addHandler(handler)
    return logger

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

_initialized = False

def get_logger(name=None, level=logging.INFO):
    """
    Возвращает logger.

    Первый вызов:
    - настраивает логгер через setup_logger()

    Дальше:
    - просто возвращает logging.getLogger(name)
    """

    global _initialized

    if not _initialized:
        setup_logger(level=level)
        _initialized = True

    return logging.getLogger(name)
