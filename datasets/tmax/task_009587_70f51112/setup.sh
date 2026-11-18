#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import json
import random

data = [
    # web-1
    {"ts": 100, "host": "web-\\u0031", "cpu": 10.0, "latency": 100.0},
    {"ts": 101, "host": "web-\\u0031", "cpu": 10.0, "latency": 100.0},
    {"ts": 102, "host": "web-\\u0031", "cpu": 10.0, "latency": 100.0},
    {"ts": 103, "host": "web-\\u0031", "cpu": 10.0, "latency": 100.0},
    {"ts": 104, "host": "web-\\u0031", "cpu": 90.0, "latency": 200.0},
]

data += [
    # web-2
    {"ts": 100, "host": "web-\\u0032", "cpu": 10.0, "latency": 160.0},
    {"ts": 101, "host": "web-\\u0032", "cpu": 10.0, "latency": 160.0},
    {"ts": 102, "host": "web-\\u0032", "cpu": 10.0, "latency": 160.0},
    {"ts": 103, "host": "web-\\u0032", "cpu": 10.0, "latency": 160.0},
    {"ts": 104, "host": "web-\\u0032", "cpu": 90.0, "latency": 160.0},
]

random.seed(42)
random.shuffle(data)

with open('/home/user/telemetry.jsonl', 'w') as f:
    for row in data:
        f.write(json.dumps(row) + '\n')
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
