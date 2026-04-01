import logging
import sys
import os

# Принудительно включаем цвета для Python
os.environ['PYTHONIOENCODING'] = 'utf-8'

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
        # Принудительно получаем сообщение
        msg = record.getMessage()

        # Форматируем без лишних проверок
        timestamp = self.formatTime(record, self.datefmt)
        color = self.LEVEL_COLORS.get(record.levelno, '')

        # Собираем строку с ANSI кодами напрямую
        if color:
            result = f"[{timestamp}] {record.levelname}: {color}{msg}{Colors.RESET}"
        else:
            result = f"[{timestamp}] {record.levelname}: {msg}"

        return result

def setup_logger(name=None, level=logging.INFO):
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.handlers.clear()

    # Используем unbuffered вывод
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)
    handler.setFormatter(ColoredFormatter(datefmt='%H:%M:%S'))

    logger.addHandler(handler)
    return logger
