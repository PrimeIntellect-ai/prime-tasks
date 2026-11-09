#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensor.log
[INFO] 2023-10-01T12:00:02Z - System boot
[DATA] 2023-10-01T12:00:02Z - payload: {"sensor_id": "T1", "temp": 10.0}
[WARN] 2023-10-01T12:00:08Z - Voltage drop
[DATA] 2023-10-01T12:00:15Z - payload: {"sensor_id": "T1", "temp": 23.0}
[DATA] 2023-10-01T12:00:30Z - payload: {"sensor_id": "T1", "temp": 15.0}
[DEBUG] 2023-10-01T12:00:33Z - Network check
[DATA] 2023-10-01T12:00:45Z - payload: {"sensor_id": "T1", "temp": 30.0}
EOF

    chmod -R 777 /home/user
