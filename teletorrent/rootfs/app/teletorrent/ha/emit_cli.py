#!/usr/bin/env python3

import sys
import json
import logging

from teletorrent.core.logger import get_logger
from teletorrent.ha.events import emit


# ------------------------------------------------------------------------------
# Logger_
# ------------------------------------------------------------------------------
log = get_logger(__name__)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def _usage() -> None:
    print("Usage: emit_cli.py <event_name> '<json_payload>'", file=sys.stderr)


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) < 2:
        _usage()
        return 1

    event_name = sys.argv[1]

    if len(sys.argv) >= 3:
        raw_payload = sys.argv[2]

        try:
            data = json.loads(raw_payload)

            if not isinstance(data, dict):
                log("Payload must be JSON object")
                return 1

        except json.JSONDecodeError as exc:
            log(f"Invalid JSON payload: {exc}")
            return 1
    else:
        data = {}

    emit(event_name, data)
    return 0


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

if __name__ == "__main__":
    sys.exit(main())
