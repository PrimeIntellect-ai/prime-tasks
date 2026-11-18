#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensors.csv
device_id,region,t1,t2,t3,t4
A100,US-EAST,45.2,55.1,40.0,60.2
B200,US-WEST,30.0,35.0,40.0,45.0
C300,EU-WEST,80.1,20.0,90.5,10.0
A100,US-EAST,55.1,10.0,10.0,10.0
D400,US-WEST,60.0,70.0,80.0,90.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
