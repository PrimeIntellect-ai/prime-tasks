#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/sensor_data/data_0.csv
1,10.0
5,12.0
9,11.0
EOF

    cat << 'EOF' > /home/user/sensor_data/data_1.csv
2,20.0
6,18.0
10,22.0
EOF

    cat << 'EOF' > /home/user/sensor_data/data_2.csv
3,15.0
7,14.0
11,16.0
EOF

    cat << 'EOF' > /home/user/sensor_data/data_3.csv
4,30.0
8,28.0
12,32.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
