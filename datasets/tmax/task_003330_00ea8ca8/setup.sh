#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,metadata,temp_loc1,temp_loc2,temp_loc3
2023-10-01T10:15:00Z,batchA,22.5,23.0,21.0
2023-10-01T10:45:00Z,batchA,23.5,24.0,22.0
2023-10-01T10:15:00Z,batchA,22.5,23.0,21.0
2023-10-01T10:55:00Z,batchA,24.5,25.0,23.0
2023-10-01T11:05:00Z,batchB,20.0,21.0,19.0
2023-10-01T11:25:00Z,batchB,21.0,22.0,20.0
2023-10-01T11:05:00Z,batchB,20.0,21.0,19.0
EOF

    chmod -R 777 /home/user
