#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/measurements.csv
SensorA,SensorB
10.5,9.2
11.1,10.0
9.8,10.2
12.0,11.5
10.3,9.5
9.9,9.0
10.7,9.8
11.2,10.1
10.0,9.1
10.5,10.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
