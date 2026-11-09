#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,temp_A,temp_B,temp_C
2023-10-01T10:00:00Z,20.5,15.0,
2023-10-01T10:01:00Z,,15.2,10.0
2023-10-01T10:02:00Z,21.0,,10.5
2023-10-01T10:03:00Z,21.5,15.8,11.0
EOF

    chmod -R 777 /home/user
