import os
import json
import urllib.request
import logging

# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

DOMAIN = "tg2transmission"
SUPERVISOR_URL = "http://supervisor/core/api/events"
TIMEOUT = 3

# ------------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------------

_TOKEN = os.getenv("SUPERVISOR_TOKEN")
_ENABLED = bool(_TOKEN)

_logger = logging.getLogger("tg2transmission.events")

# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------

def _build_event_name(name: str) -> str:
    return f"{DOMAIN}.{name}"


def _post(event_type: str, payload: dict) -> None:
    url = f"{SUPERVISOR_URL}/{event_type}"
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    urllib.request.urlopen(req, timeout=TIMEOUT).close()

# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

def emit(name: str, data: dict | None = None) -> None:
    """Send event to Home Assistant event bus."""

    if not _ENABLED:
        return

    try:
        event_type = _build_event_name(name)
        _post(event_type, data or {})

        _logger.info(f"Event sent: {event_type}")

    except Exception as exc:
        # не валим сервис
        _logger.warning(f"Event send failed: {exc}")
