#!/usr/bin/env python3

import os
import subprocess
import sys
import json

def main():
    if len(sys.argv) < 4:
        return

    level, title, message = sys.argv[1:4]

    service = os.getenv("NOTIFY_SERVICE", "")
    token = os.getenv("SUPERVISOR_TOKEN", "")

    if not service or not token:
        return

    payload = json.dumps({
        "title": title,
        "message": message
    })

    subprocess.run([
        "curl", "-s",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json",
        "-X", "POST",
        "-d", payload,
        f"http://supervisor/core/api/services/notify/{service}"
    ])



if __name__ == "__main__":
    main()
