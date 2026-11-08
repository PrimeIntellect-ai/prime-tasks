#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create the vulnerable Python script
    cat << 'EOF' > /home/user/process_telemetry.py
import sys

_error_cache = []

def parse_telemetry(file_path):
    global _error_cache
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split('|')
            if len(parts) != 3:
                continue

            record_id, timestamp, data = parts

            # Edge case format parsing bug:
            # We cache ERROR_CODE_99 for "later processing" but never clear it, causing a leak.
            if "ERROR_CODE_99" in data:
                _error_cache.append(line)

            # Normal processing would happen here
            pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        parse_telemetry(sys.argv[1])
EOF

    # 2. Create the simulated memory dump
    python3 -c '
import random
import string

dump_path = "/home/user/service_mem.dump"
leaked_string = b"TEL_8472|2023-11-01T15:30:00|ERROR_CODE_99: malformed_payload_data"

with open(dump_path, "wb") as f:
    for _ in range(5000):
        # Write some random binary noise
        f.write(bytes([random.randint(0, 255) for _ in range(50)]))
        # Write the leaked string
        f.write(leaked_string)
        f.write(b"\x00")

    # Write a few other strings to ensure they have to find the most frequent
    for _ in range(100):
        f.write(b"TEL_1111|2023-11-01T15:30:01|NORMAL_PAYLOAD\x00")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
