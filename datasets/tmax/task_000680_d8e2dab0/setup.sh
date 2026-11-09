#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/processed
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/data/raw/sensor_data.csv
id,timestamp,sensor,value
1,1600000000,SensorA,10.5
2,1600000000,SensorA,10.5
3,1600000010,SensorA,12.5
4,1600000005,SensorB,100.0
5,1600000005,SensorB,100.0
6,1600000020,SensorB,200.0
7,1600000020,SensorB,200.0
8,1600000020,SensorB,200.0
9,1600000050,SensorC,5.0
EOF

    chmod -R 777 /home/user
