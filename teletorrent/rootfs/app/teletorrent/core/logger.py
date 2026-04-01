import sys
from datetime import datetime

class Colors:
    RESET = '\033[0m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    MAGENTA = "\033[35m"
    BRIGHT_BLACK = '\033[90m'

class Logger:
    LEVELS = {
        'DEBUG': (10, Colors.BRIGHT_BLACK),
        'INFO': (20, Colors.GREEN),
        'WARNING': (30, Colors.YELLOW),
        'ERROR': (40, Colors.MAGENTA),
        'CRITICAL': (50, Colors.RED),
    }

    def __init__(self, level='INFO'):
        self.level_num = self.LEVELS[level][0]

    def _log(self, level_name, msg):
        if self.LEVELS[level_name][0] >= self.level_num:
            timestamp = datetime.now().strftime('%H:%M:%S')
            color = self.LEVELS[level_name][1]
            # Выводим напрямую в stdout с ANSI кодами
            sys.stdout.write(f"[{timestamp}] {level_name}: {color}{msg}{Colors.RESET}\n")
            sys.stdout.flush()

    def debug(self, msg): self._log('DEBUG', msg)
    def info(self, msg): self._log('INFO', msg)
    def warning(self, msg): self._log('WARNING', msg)
    def error(self, msg): self._log('ERROR', msg)
    def critical(self, msg): self._log('CRITICAL', msg)
