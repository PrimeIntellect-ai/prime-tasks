#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_sensors.csv
timestamp,sensor_A,sensor_B
1600000000,10.0,5.0
1600000060,12.0,9.0
1600000120,8.0,15.0
1600000180,-3.0,4.0
1600000240,0.0,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
