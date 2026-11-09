#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import random
from datetime import datetime, timedelta

def setup():
    random.seed(42)
    servers = [f"srv-{i}" for i in range(1, 51)]
    start_time = datetime(2023, 9, 30, 12, 0, 0)
    end_time = datetime(2023, 10, 8, 12, 0, 0)

    events = []
    event_counter = 0

    for srv in servers:
        current_time = start_time + timedelta(hours=random.randint(0, 48))
        current_hash = f"hash-{random.randint(1000, 9999)}"

        while current_time < end_time:
            event_id = f"evt-{event_counter}"
            event_counter += 1
            events.append({
                "timestamp": current_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "server_id": srv,
                "config_hash": current_hash,
                "event_id": event_id
            })
            if random.random() < 0.3:
                events.append({
                    "timestamp": current_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "server_id": srv,
                    "config_hash": current_hash,
                    "event_id": event_id
                })

            current_time += timedelta(minutes=random.randint(60, 1440))
            if random.random() < 0.5:
                current_hash = f"hash-{random.randint(1000, 9999)}"

    random.shuffle(events)

    with open('/home/user/raw_config_events.jsonl', 'w') as f:
        for e in events:
            f.write(json.dumps(e) + '\n')

if __name__ == "__main__":
    setup()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
