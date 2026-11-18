#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    cat << 'EOF' > /home/user/incoming/telemetry.jsonl
{"sensor_id": "Alpha", "timestamp": "2023-11-01T10:00:00Z", "value": 25.5}
{"sensor_id": "Alpha", "timestamp": "2023-11-01T10:00:00Z", "value": 25.5}
{"sensor_id": "Alpha", "timestamp": "2023-11-01T10:05:00Z", "value": 26.5}
{"sensor_id": "Beta", "timestamp": "2023-11-01T10:00:00Z", "value": 100.0}
{"sensor_id": "Beta", "timestamp": "2023-11-01T10:00:00Z", "value": 100.0}
{"sensor_id": "Beta", "timestamp": "2023-11-01T10:00:00Z", "value": 100.0}
{"sensor_id": "Beta", "timestamp": "2023-11-01T10:10:00Z", "value": 110.0}
{"sensor_id": "Gamma", "timestamp": "2023-11-01T10:00:00Z", "value": 50.0}
{"sensor_id": "Gamma", "timestamp": "2023-11-01T10:05:00Z", "value": 45.0}
{"sensor_id": "Gamma", "timestamp": "2023-11-01T10:10:00Z", "value": 55.0}
EOF

    chmod -R 777 /home/user
