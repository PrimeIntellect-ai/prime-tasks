#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T10:00:00Z,S1,22.5,45.0
2023-10-01T10:05:00Z,S1,23.0,47.5
2023-10-01T10:10:00Z,S1,22.0,46.0
2023-10-01T10:00:00Z,S2,18.0,60.0
2023-10-01T10:05:00Z,S2,18.5,62.0
2023-10-01T10:00:00Z,S3,30.0,30.0
2023-10-01T10:05:00Z,S3,31.0,35.0
2023-10-01T10:10:00Z,S3,30.5,33.0
2023-10-01T10:15:00Z,S3,29.5,34.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
