#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,temp_c,humidity_pct
2023-10-01T10:01:00Z,20.0,40.0
2023-10-01T10:04:30Z,21.0,42.0
2023-10-01 10:11:00+00:00,,45.0
2023-10-01 10:16:00+00:00,23.0,
2023-10-01T10:26:00Z,25.0,50.0
2023-10-01T10:59:00Z,22.0,48.0
EOF

    chmod -R 777 /home/user
