#!/usr/bin/env python3

import sys
import json
import logging

from events import emit


# Module logger for CLI utility
_logger = logging.getLogger("nc_user_files_backup.emit_cli")


# Print CLI usage help
# Writes message to stderr
def _usage() -> None:
    print("Usage: emit_cli.py <event_name> '<json_payload>'", file=sys.stderr)


# CLI entrypoint
# Reads event name and optional JSON payload from arguments
# Validates payload and forwards event to emit()
# Returns:
#   0 on success
#   1 on argument or JSON validation error
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
                _logger.debug("Payload must be JSON object")
                return 1

        except json.JSONDecodeError as exc:
            _logger.debug(f"Invalid JSON payload: {exc}")
            return 1
    else:
        data = {}

    emit(event_name, data)
    return 0


# Script entrypoint
# Executes main() and propagates exit code to shell
if __name__ == "__main__":
    sys.exit(main())