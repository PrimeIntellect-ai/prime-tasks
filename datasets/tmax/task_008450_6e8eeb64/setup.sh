#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_A,sensor_B,sensor_C
2023-01-01T00:00:00Z,10.5,21.0,15.0
2023-01-01T00:01:00Z,20.1,40.5,25.5
2023-01-01T00:02:00Z,-5.0,10.0,10.0
2023-01-01T00:03:00Z,30.0,60.0,34.0
2023-01-01T00:04:00Z,40.2,79.8,46.1
2023-01-01T00:05:00Z,1500.0,20.0,30.0
2023-01-01T00:06:00Z,50.9,102.1,55.0
2023-01-01T00:07:00Z,invalid,15.0,20.0
EOF

    chmod -R 777 /home/user
