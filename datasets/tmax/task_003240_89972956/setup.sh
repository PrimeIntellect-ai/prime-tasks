#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/sensor_alpha.csv
timestamp,sensor_id,temperature,humidity,status
2023-10-01T10:00:00Z,ALPHA_1,22.5,45.0,OK
2023-10-01T10:01:00Z,ALPHA_1,999.9,45.1,OK
2023-10-01T10:02:00Z,ALPHA_1,22.7,44.9,ERROR
2023-10-01T10:03:00Z,ALPHA_1,22.6,45.0,OK
2023-10-01T10:04:00Z,ALPHA_1,22.8,45.2,WARNING
EOF

    cat << 'EOF' > /home/user/raw_data/sensor_beta.csv
timestamp,sensor_id,temperature,humidity,status
2023-10-01T10:00:00Z,BETA_2,18.1,50.0,OK
2023-10-01T10:01:00Z,BETA_2,18.2,50.1,ERROR
2023-10-01T10:02:00Z,BETA_2,999.9,50.2,ERROR
2023-10-01T10:03:00Z,BETA_2,18.0,50.0,OK
EOF

    chmod -R 777 /home/user
