#!/usr/bin/env python3

import os
import sys
import requests


def main():
    if len(sys.argv) < 3:
        sys.exit(0)

    title, message = sys.argv[1:3]

    service = os.getenv("NOTIFY_SERVICE", "")
    token = os.getenv("SUPERVISOR_TOKEN", "")

    if not service or not token:
        sys.exit(0)

    url = f"http://supervisor/core/api/services/notify/{service}"

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    requests.post(url, headers=headers, json={
        "title": title,
        "message": message
    }, timeout=5)


if __name__ == "__main__":
    main()
