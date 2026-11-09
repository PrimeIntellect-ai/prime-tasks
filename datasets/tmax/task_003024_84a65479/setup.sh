#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/data/raw_sensors.jsonl
{"timestamp": "2023-10-01T00:30:00Z", "sensor_id": "S1", "location": "N\u00f6rth", "temp": 10.0}
{"timestamp": "2023-10-01T02:15:00Z", "sensor_id": "S1", "location": "S\uXXth", "temp": 12.5}
{"timestamp": "2023-10-01T05:45:00Z", "sensor_id": "S1", "location": "East", "temp": 15.0}
{"timestamp": "2023-10-01T01:15:00Z", "sensor_id": "S2", "location": "W\u00e9st", "temp": 20.0}
{"timestamp": "2023-10-01T04:10:00Z", "sensor_id": "S2", "location": "W\uYYst", "temp": 22.0}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/workspace
    chmod -R 777 /home/user
