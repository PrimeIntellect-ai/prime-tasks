#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensor_data.csv
F1,F2,F3,F4
1.2,2.1,3.3,4.1
1.5,2.5,3.0,4.6
-9999,2.1,3.2,4.4
2.0,3.0,2.9,4.7
2.5,3.6,2.8,4.8
1.0,2.0,3.1,4.5
-9999,-9999,-9999,-9999
1.8,2.7,2.9,4.5
2.2,3.1,3.0,4.9
1.1,1.9,3.5,4.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
