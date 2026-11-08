#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_stream.jsonl
{"sensor_id": "S01", "temperature": 20.0, "meta": "init"}
{"sensor_id": "S02", "temperature": 22.0, "meta": "bad \uZZZZ unicode"}
{"sensor_id": "S03", "temperature": 25.0, "meta": "ok"}
{"sensor_id": "S04", "temperature": 27.0, "meta": "normal"}
{"sensor_id": "S05", "temperature": 30.0, "meta": "invalid \u123"}
{"sensor_id": "S06", "temperature": 23.0, "meta": "good"}
{"sensor_id": "S07", "temperature": 28.0, "meta": "final"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
