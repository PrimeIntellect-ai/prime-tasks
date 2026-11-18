#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import os
import random

random.seed(42)

log_entries = []
notes_choices = [
    "Warning: High humidity! recalibration needed.",
    "All systems nominal.",
    "ERROR 404 - Network disconnect.",
    "Sensor ping timeout; retrying...",
    "Maintenance required (dust buildup)."
]

with open("/home/user/raw_sensor_logs.txt", "w") as f:
    for i in range(50000):
        if random.random() < 0.05:
            # Inject invalid line
            f.write(f"Corrupted log entry {random.randint(100, 999)} at unknown time\n")
            continue

        year = 2023
        month = random.randint(1, 12)
        day = random.randint(1, 28)
        hour = random.randint(0, 23)
        minute = random.randint(0, 59)
        second = random.randint(0, 59)

        sensor = f"Sensor-{random.randint(1, 50)}"
        temp_f = round(random.uniform(-20.0, 120.0), 1)
        notes = random.choice(notes_choices)

        line = f"[{year}/{month:02d}/{day:02d}-{hour:02d}:{minute:02d}:{second:02d}] | SENSOR_ID: {sensor} | TEMP: {temp_f}F | NOTES: \"{notes}\"\n"
        f.write(line)
EOF

    python3 /tmp/setup_logs.py
    rm /tmp/setup_logs.py

    chmod -R 777 /home/user
