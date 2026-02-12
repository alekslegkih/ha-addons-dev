import os
import json
import urllib.request
import urllib.error
import logging


DOMAIN = "backup_sync"
SUPERVISOR_URL = "http://supervisor/core/api/events"
TIMEOUT = 2


_TOKEN = os.getenv("SUPERVISOR_TOKEN")
_ENABLED = bool(_TOKEN)

_logger = logging.getLogger("backup_sync.events")


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

    with urllib.request.urlopen(req, timeout=TIMEOUT):
        pass


def emit(name: str, data: dict | None = None) -> None:
    """
    Send event to Home Assistant event bus.

    Usage:
        emit("storage_failed", {"reason": "no_device_configured"})
    """

    if not _ENABLED:
        return

    try:
        event_type = _build_event_name(name)
        _post(event_type, data or {})
    except Exception as e:
        # Не валим демон, только логируем
        _logger.debug(f"Event send failed: {e}")
