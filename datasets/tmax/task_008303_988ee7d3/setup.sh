#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
raw_log,raw_value
"System init [2023-01-01 00:00:00] OK","Sensor reporting T:10.0C today"
"System check [2023-01-01 01:00:00] OK","Sensor reporting T:12.0C today"
"Garbage line with no date","Error: Sensor disconnected"
"System check [2023-01-01 05:00:00] OK","Sensor reporting T:20.0C today"
"System check [2023-01-01 06:00:00] OK","Sensor reporting T:22.0C today"
"Duplicate hour [2023-01-01 06:15:00] OK","Sensor reporting T:24.0C today"
EOF

    chmod -R 777 /home/user
