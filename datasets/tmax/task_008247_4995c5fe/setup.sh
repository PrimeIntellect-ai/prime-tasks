#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/data_01.jsonl
{"ts": "2023-10-01T10:00:00.100Z", "sensor_id": "A", "value": 10.0}
{"ts": "2023-10-01T10:00:00.100Z", "sensor_id": "A", "value": 10.0}
{"ts": "2023-10-01T10:00:01.900Z", "sensor_id": "A", "value": 12.0}
{"ts": "2023-10-01T10:00:03.000Z", "sensor_id": "A", "value": null}
{"sensor_id": "A", "value": 5.0}
EOF

    cat << 'EOF' > /home/user/raw_data/data_02.jsonl
{"ts": "2023-10-01T10:00:02.050Z", "sensor_id": "A", "value": 25.0}
{"ts": "2023-10-01T10:00:04.000Z", "sensor_id": "B", "value": 50.0}
{"ts": "2023-10-01T10:00:05.100Z", "sensor_id": "B", "value": 20.0}
{"ts": "2023-10-01T10:00:05.800Z", "sensor_id": "B", "value": 40.0}
EOF

    chmod -R 777 /home/user
