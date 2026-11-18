#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk bc datamash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/telemetry.jsonl
{"ts": "2023-10-15T12:15:00Z", "device": "DEV01", "val": 10.0, "msg": "Normal operation"}
{"ts": "2023-10-15T12:45:00Z", "device": "DEV01", "val": 12.0, "msg": "Normal operation"}
{"ts": "2023-10-15T12:50:00Z", "device": "DEV01", "val": 8.0, "msg": "Bad escape \uGHIJ"}
{"ts": "2023-10-15T13:10:00Z", "device": "DEV01", "val": 20.0, "msg": "Normal operation"}
{"ts": "2023-10-15T13:30:00Z", "device": "DEV02", "val": 15.0, "msg": "Normal operation"}
{"ts": "2023-10-15T14:05:00Z", "device": "DEV01", "val": 30.0, "msg": "Normal operation"}
{"ts": "2023-10-15T14:45:00Z", "device": "DEV01", "val": 40.0, "msg": "Bad escape \uXXXX"}
{"ts": "2023-10-15T15:15:00Z", "device": "DEV01", "val": 15.0, "msg": "Normal operation"}
{"ts": "2023-10-15T16:20:00Z", "device": "DEV01", "val": 10.0, "msg": "Normal operation"}
{"ts": "2023-10-15T13:45:00Z", "device": "DEV02", "val": 17.0, "msg": "Normal operation"}
{"ts": "2023-10-15T14:15:00Z", "device": "DEV02", "val": 20.0, "msg": "Normal operation"}
{"ts": "2023-10-15T15:05:00Z", "device": "DEV02", "val": 25.0, "msg": "Normal operation"}
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
