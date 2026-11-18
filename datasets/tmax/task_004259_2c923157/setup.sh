#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sensors.csv
timestamp,sensor_id,temperature,pressure
2023-10-01T00:00,1,20.5,101.3
2023-10-01T01:00,2,22.1,101.5
2023-10-01T02:00,1,21.0,101.4
2023-10-01T03:00,3,19.8,101.1
2023-10-01T04:00,A,20.0,101.2
2023-10-01T05:00,1,,101.2
2023-10-01T06:00,2,25.0,bad
2023-10-01T07:00,3,23.5,101.7
2023-10-01T08:00,4,21.0,101.3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
