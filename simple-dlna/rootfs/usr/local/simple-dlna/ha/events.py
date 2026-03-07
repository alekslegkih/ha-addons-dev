import os
import json
import urllib.request
import urllib.error
import logging


# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

DOMAIN = "simple-dlna"
SUPERVISOR_URL = "http://supervisor/core/api/events"
TIMEOUT = 2


# ------------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------------

_TOKEN = os.getenv("SUPERVISOR_TOKEN")
_ENABLED = bool(_TOKEN)

_logger = logging.getLogger("simple-dlna.events")

_logger.debug(f"Events module initialized: enabled={_ENABLED}")


# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------

def _build_event_name(name: str) -> str:
    event_name = f"{DOMAIN}.{name}"
    _logger.debug(f"Built event name={event_name}")
    return event_name


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


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

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
