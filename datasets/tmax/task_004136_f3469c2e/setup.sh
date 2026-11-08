#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr cron fonts-dejavu
    pip3 install pytest

    mkdir -p /app
    mkdir -p /opt

    # Generate the image with the hidden configuration
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -annotate +20+40 "CONFIGURATION SHEET" \
        -annotate +20+80 "W_SIZE: 5" \
        -annotate +20+110 "THRESH_MULT: 0.25" \
        -annotate +20+140 "FMT: \"[{timestamp}] {sensor_id} -> M:{mean:.2f} S:{status}\"" \
        /app/sensor_config.png

    # Create the Oracle
    cat << 'EOF' > /opt/oracle_cleaner.py
import sys
import json
from collections import defaultdict, deque

W_SIZE = 5
THRESH_MULT = 0.25
FMT = "[{timestamp}] {sensor_id} -> M:{mean:.2f} S:{status}"

history = defaultdict(lambda: deque(maxlen=W_SIZE))

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        sensor_id = data['sensor_id']
        timestamp = data['timestamp']
        value = float(data['value'])
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        continue

    history[sensor_id].append(value)

    mean = sum(history[sensor_id]) / len(history[sensor_id])

    if abs(value - mean) > (THRESH_MULT * mean):
        status = "ANOMALY"
    else:
        status = "OK"

    print(FMT.format(timestamp=timestamp, sensor_id=sensor_id, mean=mean, status=status))
EOF
    chmod +x /opt/oracle_cleaner.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
