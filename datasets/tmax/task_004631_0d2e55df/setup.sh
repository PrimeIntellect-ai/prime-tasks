#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-setuptools
    pip3 install pytest

    mkdir -p /app/lib_dataclean

    cat << 'EOF' > /app/lib_dataclean/setup.py
from setuptools import setup

setup(
    name='lib_dataclean',
    version='1.0.0',
    py_modules=['cleaner'],
)
EOF

    cat << 'EOF' > /app/lib_dataclean/cleaner.py
class Deduplicator:
    def __init__(self):
        self.last_row = None
    def is_duplicate(self, row):
        if row == self.last_row:
            return False # DELIBERATE BUG: Should return True
        self.last_row = row
        return False
EOF

    cat << 'EOF' > /app/device_map.json
{
  "DEV_A": "North_Wing",
  "DEV_B": "South_Wing",
  "DEV_C": "East_Wing",
  "DEV_D": "West_Wing"
}
EOF

    cat << 'EOF' > /app/oracle_bin
#!/usr/bin/env python3
import sys
import json
from collections import defaultdict, deque

def main():
    with open('/app/device_map.json') as f:
        device_map = json.load(f)

    last_row = None
    windows = defaultdict(lambda: deque(maxlen=5))

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        parts = line.split(',')
        if len(parts) != 3:
            continue

        ts, dev, reading = parts

        try:
            val = int(reading)
        except ValueError:
            continue

        row = (ts, dev, reading)
        if row == last_row:
            continue
        last_row = row

        windows[dev].append(val)
        w_sum = sum(windows[dev])
        if w_sum >= 100:
            loc = device_map.get(dev, "UNKNOWN")
            print(f"{ts},{dev},{loc},{w_sum}")

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
