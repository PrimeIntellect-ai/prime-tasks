#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensors.jsonl
{"event_id": 1, "sensor_val": 45.2, "note": "all clear"}
{"event_id": 2, "sensor_val": 41.0, "note": "bad \u12G4 sequence"}
{"event_id": 3, "sensor_val": 48.9, "note": "good \u0041"}
{"event_id": 4, "sensor_val": 39.5, "note": "short \u12"}
{"event_id": 5, "sensor_val": 12.1, "note": "multiple \uABCD and \u0000"}
{"event_id": 6, "sensor_val": 99.9, "note": "bad ending \u123"}
EOF

    chmod -R 777 /home/user
