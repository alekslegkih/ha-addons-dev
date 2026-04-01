# В файле core/logger.py
import os
from datetime import datetime

class Logger:
    RESET   = "\033[0m"
    WHITE   = "\033[37m"
    GREEN   = "\033[32m"
    YELLOW  = "\033[33m"
    RED     = "\033[31m"
    BLUE    = "\033[34m"
    MAGENTA = "\033[35m"

    def __init__(self, name=None, show_timestamp=True, timestamp_format="%H:%M:%S"):
        """
        Инициализация логгера

        Args:
            name: имя логгера (__name__)
            show_timestamp: показывать ли временную метку
            timestamp_format: формат временной метки
        """
        self.name = name
        self.show_timestamp = show_timestamp
        self.timestamp_format = timestamp_format

    def _get_timestamp(self):
        """Получить отформатированную временную метку с белым цветом"""
        if self.show_timestamp:
            timestamp = datetime.now().strftime(self.timestamp_format)
            return f"{self.WHITE}[{timestamp}]{self.RESET} "
        return ""

    def _get_prefix(self):
        """Получить префикс с именем логгера"""
        if self.name:
            return f"[{self.name}] "
        return ""

    def _print(self, color, msg):
        """Печать сообщения с цветным текстом и белым таймштампом"""
        timestamp = self._get_timestamp()
        prefix = self._get_prefix()
        print(f"{timestamp}{prefix}{color}{msg}{self.RESET}", flush=True)

    def log(self, msg):
        """Обычное сообщение без цвета"""
        timestamp = self._get_timestamp()
        prefix = self._get_prefix()
        print(f"{timestamp}{prefix}{msg}", flush=True)

    def info(self, msg):
        self._print(self.GREEN, msg)

    def warning(self, msg):
        self._print(self.YELLOW, msg)

    def error(self, msg):
        self._print(self.RED, msg)

    def debug(self, msg):
        self._print(self.MAGENTA, msg)

# Фабричная функция для создания логгеров
def get_logger(name=None, show_timestamp=True, timestamp_format="%H:%M:%S"):
    """Создает и возвращает новый экземпляр логгера"""
    return Logger(name=name, show_timestamp=show_timestamp, timestamp_format=timestamp_format)

# Создаем глобальный экземпляр для простого использования
logger = Logger()
