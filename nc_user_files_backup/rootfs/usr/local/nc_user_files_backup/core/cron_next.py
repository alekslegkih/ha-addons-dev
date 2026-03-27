#!/usr/bin/env python3

"""
Compute next execution time from cron expression.

Input:
    argv[1] - cron schedule string (e.g. "47 2 * * *")
    argv[2] - base timestamp (unix seconds)

Output:
    Prints next run timestamp (unix seconds) to stdout

Exit codes:
    0 - success
    1 - invalid input or computation error
"""

import sys
from datetime import datetime
from croniter import croniter


def main():
    try:
        schedule = sys.argv[1]
        base_ts = int(sys.argv[2])
    except (IndexError, ValueError):
        sys.exit(1)

    try:
        base_dt = datetime.fromtimestamp(base_ts)
        itr = croniter(schedule, base_dt)
        next_dt = itr.get_next(datetime)
        next_ts = int(next_dt.timestamp())
    except Exception:
        sys.exit(1)

    print(next_ts)


if __name__ == "__main__":
    main()
