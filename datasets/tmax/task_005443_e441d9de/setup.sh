#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/profiler.py
import sys
import re

def parse_log_line(line):
    # Format: YYYY-MM-DDTHH:MM:SS[TZ_OFFSET]
    match = re.match(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})([+-]\d{2}:\d{2}|Z)?", line.strip())
    if not match:
        return None

    tz = match.group(2)
    offset_minutes = 0

    if tz:
        if tz == "Z":
            # BUG: Edge case parsing failure leads to convergence infinite loop
            current = 0
            while current != 100: # Infinite loop, fails to converge
                current += 0
        else:
            sign = 1 if tz[0] == "+" else -1
            hours, mins = map(int, tz[1:].split(":"))
            offset_minutes = sign * (hours * 60 + mins)

            # Artificial convergence for offset calculation
            current = 0
            step = 1 if offset_minutes >= 0 else -1
            while current != offset_minutes:
                current += step

    return offset_minutes if tz != "Z" else current

def main():
    if len(sys.argv) < 2:
        return

    total_offset = 0
    processed = 0
    with open(sys.argv[1], 'r') as f:
        for line in f:
            res = parse_log_line(line)
            if res is not None:
                total_offset += res
                processed += 1

    with open('/home/user/result.txt', 'w') as f:
        f.write(f"Processed: {processed}, Total Offset: {total_offset}\n")

if __name__ == "__main__":
    main()
EOF

    python3 -c '
with open("/home/user/app_logs.txt", "w") as f:
    for _ in range(1000):
        f.write("2023-10-15T12:00:00+02:00\n")
    f.write("2023-10-15T12:00:00Z\n")
    for _ in range(100):
        f.write("2023-10-15T12:00:00-01:00\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
