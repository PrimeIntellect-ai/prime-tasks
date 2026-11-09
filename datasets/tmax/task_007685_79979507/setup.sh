#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data /home/user/logs
    cat << 'EOF' > /home/user/data/raw_sensors.csv
timestamp,sensor_a,sensor_b,sensor_c
1600000000,10.0,20.0,50.0
1600000001,,22.0,150.0
1600000002,12.0,,40.0
1600000003,15.0,25.0,200.0
1600000004,11.0,21.0,90.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
