#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.jsonl
{"time": "2023-10-12T08:14:05Z", "device": "alpha", "temp": 22.5, "humidity": 45.1, "note": "check \uX123 fail"}
{"time": "2023-10-12T08:55:10Z", "device": "beta", "temp": 23.0, "humidity": 44.0, "note": "ok"}
{"time": "2023-10-12T09:05:00Z", "device": "alpha", "temp": 22.8, "humidity": 46.2, "note": "warn \uX999"}
{"time": "2023-10-12T09:45:22Z", "device": "gamma", "temp": 19.5, "humidity": 50.0, "note": "sys \uX000 error"}
EOF

    chmod -R 777 /home/user
