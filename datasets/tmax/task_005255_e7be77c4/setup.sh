#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg espeak
    pip3 install pytest

    mkdir -p /app

    # Generate CSV
    cat << 'EOF' > /tmp/gen_csv.py
import csv
import random

random.seed(42)
data = []
# Base sequence from 1680000000 to 1680000020
for i in range(21):
    if i in [5, 6, 7]: continue # Create a gap to be forward-filled
    ts_ms = 1680000000000 + (i * 1000) + random.randint(-100, 100) # Jitter
    val = 10.0 + i
    data.append((ts_ms, val))

    # Simulate ETL duplicates
    if i % 4 == 0:
        data.append((ts_ms + random.randint(10, 50), val - 2.0))
        data.append((ts_ms - random.randint(10, 50), val + 1.5)) # This should be the max for duplicates

with open('/app/sensor_raw.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp_ms', 'value'])
    for row in sorted(data, key=lambda x: x[0]):
        writer.writerow(row)
EOF
    python3 /tmp/gen_csv.py

    # Generate WAV
    espeak -w /app/corrections.wav "Calibration update. Timestamp one six eight zero zero zero zero zero zero six has value ninety nine point nine. Also timestamp one six eight zero zero zero zero zero one five has value zero point five."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
