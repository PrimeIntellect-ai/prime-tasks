#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import json
import random

random.seed(42)

base_latency = 100

with open('/home/user/access_logs.jsonl', 'w') as f:
    for i in range(1, 1001):
        # Generate an anomaly for 5 specific indices
        if i in [75, 200, 450, 800, 950]:
            latency = base_latency * 4 + random.randint(10, 50)
        else:
            latency = base_latency + random.randint(-10, 10)

        ip = f"10.0.{i%256}.{i%256}"
        timestamp = f"2023-10-01T12:00:{i%60:02d}Z"

        log = {
            "timestamp": timestamp,
            "ip": ip,
            "latency_ms": latency,
            "status": 200
        }
        f.write(json.dumps(log) + '\n')
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
