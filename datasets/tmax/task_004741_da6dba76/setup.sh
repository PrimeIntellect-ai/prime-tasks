#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/measurements.jsonl
{"ts": "2023-10-01T10:05:00", "vehicle_id": "V1", "speed": 40.0, "temp": 20.0}
{"ts": "2023-10-01T10:15:00", "vehicle_id": "V1", "speed": null, "temp": 22.0}
{"ts": "2023-10-01T10:25:00", "vehicle_id": "V1", "speed": 60.0, "temp": 21.0}
{"ts": "2023-10-01T10:25:00", "vehicle_id": "V1", "speed": 60.0, "temp": 21.0}
{"ts": "2023-10-01T11:05:00", "vehicle_id": "V1", "speed": 50.0, "temp": 25.0}
{"ts": "2023-10-01T11:35:00", "vehicle_id": "V1", "speed": 70.0, "temp": 26.0}
{"ts": "2023-10-01T10:10:00", "vehicle_id": "V2", "speed": 30.0, "temp": 18.0}
{"ts": "2023-10-01T10:30:00", "vehicle_id": "V2", "speed": 40.0, "temp": 19.0}
EOF

    chmod -R 777 /home/user
