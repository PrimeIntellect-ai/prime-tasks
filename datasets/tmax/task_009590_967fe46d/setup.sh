#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/telemetry.jsonl
{"ts": "2023-10-01T10:15:00Z", "device": "sensor_A", "val": 20.0}
{"ts": "2023-10-01T11:45:00Z", "device": "sensor_A", "val": 22.0}
{"ts": "2023-10-01T12:10:00Z", "device": "sensor_A", "val": 21.0}
{"ts": "2023-10-01T13:05:00Z", "device": "sensor_A", "val": 35.0}
{"ts": "2023-10-01T13:55:00Z", "device": "sensor_A", "val": 34.0}
{"ts": "2023-10-01T10:05:00Z", "device": "sensor_B", "val": 15.0}
{"ts": "2023-10-01T10:55:00Z", "device": "sensor_B", "val": 17.0}
{"ts": "2023-10-01T11:30:00Z", "device": "sensor_B", "val": 16.0}
{"ts": "2023-10-01T12:05:00Z", "device": "sensor_B", "val": 16.0}
{"ts": "2023-10-01T13:15:00Z", "device": "sensor_B", "val": 5.0}
EOF

    chmod -R 777 /home/user
