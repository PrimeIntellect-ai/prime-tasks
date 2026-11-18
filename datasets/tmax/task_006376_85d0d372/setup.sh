#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_fleet_data.csv
timestamp,V1_speed,V1_temp,V2_speed,V2_temp
2023-01-01T10:00:00,45,22,60,20
2023-01-01T10:05:00,50,23,55,21
2023-01-01T10:10:00,55,25,65,22
2023-01-01T10:15:00,40,24,70,23
2023-01-01T10:20:00,60,26,50,19
EOF

    chmod -R 777 /home/user
