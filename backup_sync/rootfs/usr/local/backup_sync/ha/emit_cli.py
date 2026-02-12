#!/usr/bin/env python3

import sys
import json
import logging

from events import emit


_logger = logging.getLogger("backup_sync.emit_cli")


def _usage():
    print("Usage: emit_cli.py <event_name> '<json_payload>'", file=sys.stderr)


def main():
    # Минимальная проверка аргументов
    if len(sys.argv) < 2:
        _usage()
        return 1

    event_name = sys.argv[1]

    # Payload опционален
    if len(sys.argv) >= 3:
        raw_payload = sys.argv[2]

        try:
            data = json.loads(raw_payload)
            if not isinstance(data, dict):
                _logger.debug("Payload must be JSON object")
                return 1
        except json.JSONDecodeError as e:
            _logger.debug(f"Invalid JSON payload: {e}")
            return 1
    else:
        data = {}

    emit(event_name, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
