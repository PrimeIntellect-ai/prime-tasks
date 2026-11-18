#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import json
import random
from datetime import datetime, timedelta

start_time = datetime(2023, 10, 1, 10, 0, 0)
events = []

# Generate events, skipping minutes 10:04, 10:07, and 10:12
for m in range(15):
    if m in [4, 7, 12]:
        continue

    num_events = random.randint(10, 50)
    for _ in range(num_events):
        second = random.randint(0, 59)
        ts = start_time + timedelta(minutes=m, seconds=second)
        events.append({
            "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "user_email": f"user{random.randint(1,1000)}@company.com",
            "ip_address": f"10.0.{random.randint(0,255)}.{random.randint(1,254)}",
            "event_type": "translation_view",
            "ui_string_id": f"str_{random.randint(100,999)}"
        })

# Sort by timestamp to simulate real log stream
events.sort(key=lambda x: x["timestamp"])

with open("/home/user/raw_events.jsonl", "w") as f:
    for e in events:
        f.write(json.dumps(e) + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
