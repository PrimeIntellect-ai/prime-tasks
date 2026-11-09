#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "sensor_id": "A1", "reading": 10.0}
{"timestamp": "2023-10-01T10:01:00Z", "sensor_id": "A1", "reading": 20.0, "note": "broken \u12"}
{"timestamp": "2023-10-01T10:02:00Z", "sensor_id": "A1", "reading": 15.0}
{"timestamp": "2023-10-01T10:03:00Z", "sensor_id": "A1", "reading": 30.0}
{"timestamp": "2023-10-01T10:04:00Z", "sensor_id": "A1", "reading": 25.0, "bad_field": "\uZZZZ"}
{"timestamp": "2023-10-01T10:05:00Z", "sensor_id": "A1", "reading": 12.0}
{"timestamp": "2023-10-01T10:06:00Z", "sensor_id": "A1", "reading": 18.0}
EOF

    chmod -R 777 /home/user
