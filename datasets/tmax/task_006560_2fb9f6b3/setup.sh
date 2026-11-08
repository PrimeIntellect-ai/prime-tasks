#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.jsonl
{"event_id": "e1", "timestamp": "2023-10-01T12:00:00Z", "sensor_data": {"temperature_f": 32.0}, "user_agent": "ModelA/1.0"}
{"event_id": "e2", "timestamp": "", "sensor_data": {"temperature_f": 212.0}, "user_agent": "ModelB/2.0"}
{"event_id": "e1", "timestamp": "2023-10-01T12:00:05Z", "sensor_data": {"temperature_f": 32.0}, "user_agent": "ModelA/1.0"}
{"event_id": "e3", "timestamp": "2023-10-01T12:00:10Z", "sensor_data": {"temperature_f": 98.6}, "user_agent": "ModelC-Pro/3.1.4"}
{"event_id": "e4", "timestamp": "2023-10-01T12:00:15Z", "sensor_data": {"temperature_f": -40.0}, "user_agent": "Legacy/9.9/beta"}
EOF

    chmod -R 777 /home/user
