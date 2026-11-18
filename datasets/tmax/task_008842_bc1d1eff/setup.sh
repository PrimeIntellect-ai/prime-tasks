#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.txt
S2 1601 20
S1 1600 50
S3 1500 100
S4 1600 0
S1 1603 60
S3 1503 110
S1 1602 53
S4 1601 1
S2 1600 10
S3 1502 103
S1 1601 55
S2 1602 30
S3 1501 105
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
