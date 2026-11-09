#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pytz

    mkdir -p /home/user/data
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/process_telemetry.py
import sys
import json
import pytz
from datetime import datetime

def parse_log_line(line):
    parts = line.strip().split('|')
    if len(parts) != 4:
        return None

    dt_str, tz_str, device_id, value = parts
    tz = pytz.timezone(tz_str)

    dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
    # BUG: localize raises AmbiguousTimeError during DST fallback
    localized_dt = tz.localize(dt)

    return {
        "timestamp": localized_dt.isoformat(),
        "device_id": device_id,
        "value": float(value)
    }

def main(input_file, output_file):
    results = []
    with open(input_file, 'r') as f:
        for line in f:
            parsed = parse_log_line(line)
            if parsed:
                results.append(parsed)

    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python process_telemetry.py <input> <output>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
EOF

    cat << 'EOF' > /home/user/data/telemetry.txt
2023-11-04 14:00:00|America/New_York|DEV-1111|42.5
2023-11-05 01:30:00|America/New_York|DEV-8932|12.1
2023-11-06 09:15:00|America/New_York|DEV-2222|99.9
EOF

    dd if=/dev/urandom of=/home/user/process_memory.raw bs=1K count=10 2>/dev/null
    echo 'randomgarbageCRASH_CONTEXT: {"timestamp": "2023-11-05 01:30:00", "tz": "America/New_York", "device_id": "DEV-8932"}moregarbage' >> /home/user/process_memory.raw
    dd if=/dev/urandom bs=1K count=10 2>/dev/null >> /home/user/process_memory.raw

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
