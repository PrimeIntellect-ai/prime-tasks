#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sensor_raw.log
[2023-10-12T09:12:00Z] SENSOR_LOG device=DEV01 temp=21.0 hum=40.0
[2023-10-12T09:45:30Z] SENSOR_LOG device=DEV01 temp=23.0 hum=42.0
[2023-10-12T10:05:00Z] SENSOR_LOG device=DEV02 temp=155.0 hum=50.0
[2023-10-12T10:15:00Z] SENSOR_LOG device=DEV01 temp=22.0 hum=45.0
[2023-10-12T10:30:00Z] SENSOR_LOG device=DEV02 temp=24.0 hum=55.0
[2023-10-12T10:45:00Z] SENSOR_LOG device=DEV01 temp=24.0 hum=47.0
[2023-10-12T10:55:00Z] SENSOR_LOG device=DEV02 temp=25.0 hum=60.0
[2023-10-12T11:05:00Z] SENSOR_LOG device=DEV03 temp=-60.0 hum=20.0
[2023-10-12T11:10:00Z] SENSOR_LOG device=DEV03 temp=10.0 hum=105.0
[2023-10-12T11:20:00Z] SENSOR_LOG device=DEV01 temp=20.0 hum=40.0
EOF

    chmod -R 777 /home/user
