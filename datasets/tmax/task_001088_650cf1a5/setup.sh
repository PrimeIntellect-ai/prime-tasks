#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.jsonl
{"sensor": "Temp A", "time": "2023-01-01T12:15:30Z", "value": 22.5}
{"sensor": "temp a", "time": 1672575330, "value": 23.5}
{"sensor": "Temp_A", "time": 1672576000000, "value": 24.5}
{"sensor": "Humidity B", "time": "2023-01-01T12:59:59Z", "value": 45.0}
{"sensor": "humidity_b", "time": 1672577999, "value": 46.0}
{"sensor": "Temp A", "time": "2023-01-01T13:05:00Z", "value": 25.0}
{"sensor": "Temp A", "time": "2023-01-01T13:05:00Z", "value": 99.9}
EOF

    chmod -R 777 /home/user
