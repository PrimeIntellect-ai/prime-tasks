#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed
    pip3 install pytest scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_sensors.csv
sensor_id,rack,temperature
1,A,21.1
2,A,21.5
3,A,-10.0
4,A,21.3
5,A,
6,A,21.2
7,A,21.4
8,B,21.6
9,B,21.8
10,B,0.0
11,B,21.5
12,B,21.7
13,B,21.9
EOF

    chmod -R 777 /home/user
