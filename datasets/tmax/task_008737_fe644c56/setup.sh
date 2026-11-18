#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pytz

mkdir -p /home/user/uptime_monitor

cat << 'EOF' > /home/user/uptime_monitor/monitor.py
import datetime

def calculate_uptime(start_str, end_str, downtimes):
    """
    Calculates uptime percentage.
    start_str and end_str are in format '%Y-%m-%d %H:%M:%S', assumed to be US/Eastern.
    downtimes is a list of floats in seconds.
    """
    fmt = '%Y-%m-%d %H:%M:%S'
    start = datetime.datetime.strptime(start_str, fmt)
    end = datetime.datetime.strptime(end_str, fmt)

    # BUG 1: Naive subtraction ignores DST transition
    total_seconds = (end - start).total_seconds()

    # BUG 2: Precision loss on small floats
    total_downtime = 0.0
    for dt in downtimes:
        total_downtime += dt

    if total_seconds == 0:
        return 0.0

    return 100.0 * (1.0 - (total_downtime / total_seconds))
EOF

cat << 'EOF' > /home/user/uptime_monitor/generate_report.py
import json
from monitor import calculate_uptime

def main():
    with open('events.json', 'r') as f:
        data = json.load(f)

    start = data['start']
    end = data['end']
    downtimes = data['downtimes']

    uptime = calculate_uptime(start, end, downtimes)

    with open('report.json', 'w') as f:
        json.dump({"uptime_percentage": uptime}, f)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /home/user/uptime_monitor/events.json
{
    "start": "2023-11-05 00:00:00",
    "end": "2023-11-05 03:00:00",
    "downtimes": [0.0000001]
}
EOF

# Append 9999999 more 0.0000001 to downtimes to make it exactly 1.0 second of downtime.
python3 -c "import json; d=json.load(open('/home/user/uptime_monitor/events.json')); d['downtimes'] = [0.0000001]*10000000; json.dump(d, open('/home/user/uptime_monitor/events.json', 'w'))"

# Create a binary dump with the expected string
python3 -c "with open('/home/user/uptime_monitor/crash_dump.bin', 'wb') as f: f.write(b'\x00\x01\x02' * 1000 + b'GARBAGE_DATA_LAST_PROCESSED_TS: 2023-11-05 01:23:45\x00\x00\x00' + b'\xFF' * 500)"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
