import os
import json
import urllib.request
import urllib.error
import logging

# Event domain and API configuration
DOMAIN = "nc_user_files_backup"
SUPERVISOR_URL = "http://supervisor/core/api/events"
TIMEOUT = 2

# Runtime state (Supervisor token detection)
# Events are enabled only if token is available
_TOKEN = os.getenv("SUPERVISOR_TOKEN")
_ENABLED = bool(_TOKEN)

_logger = logging.getLogger("backup_sync.events")

_logger.debug(f"Events module initialized: enabled={_ENABLED}")


# Build full event name with domain prefix
# Example:
#   storage_failed -> nc_user_files_backup.storage_failed
def _build_event_name(name: str) -> str:
    event_name = f"{DOMAIN}.{name}"
    _logger.debug(f"Built event name={event_name}")
    return event_name


# Send HTTP POST request to Home Assistant Supervisor API
# Arguments:
#   event_type - full event name
#   payload    - JSON payload (dict)
def _post(event_type: str, payload: dict) -> None:
    url = f"{SUPERVISOR_URL}/{event_type}"
    data = json.dumps(payload).encode("utf-8")

    _logger.debug(f"POST {url}")
    _logger.debug(f"Payload={payload}")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=TIMEOUT):
        _logger.debug("Event POST successful")


# Public API: emit event to Home Assistant
# Arguments:
#   name - event name (without domain)
#   data - optional payload dictionary
# Notes:
#   - does nothing if Supervisor token is not available
#   - never raises (safe for background services)
def emit(name: str, data: dict | None = None) -> None:
    """
    Send event to Home Assistant event bus.

    Example:
        emit("storage_failed", {"reason": "no_device_configured"})
    """

    if not _ENABLED:
        _logger.debug("Emit skipped: supervisor token not available")
        return

    try:
        _logger.debug(f"emit(): name={name} data={data}")

        event_type = _build_event_name(name)
        _post(event_type, data or {})

    except Exception as exc:
        # Do not crash the daemon, only log debug
        _logger.debug(f"Event send failed: {exc}")