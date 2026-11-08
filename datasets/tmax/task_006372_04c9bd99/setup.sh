#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/data/sensors.csv
id,vibration,temperature,pressure,risk
1,10,20.5,100.0,5.2
2,NaN,22.1,101.2,6.1
3,12,21.0,99.5,5.5
4,15,23.5,102.1,7.0
5,8,19.0,98.0,4.5
6,NaN,19.5,98.5,4.8
7,14,22.8,101.8,6.8
8,9,20.0,99.0,5.0
9,11,21.5,100.5,5.8
10,NaN,20.8,100.2,5.4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
