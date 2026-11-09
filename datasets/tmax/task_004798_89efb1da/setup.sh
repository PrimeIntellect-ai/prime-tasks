#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/metrics.csv
cpu,mem,latency
2.0,5.0,12.0
4.0,3.0,14.0
6.0,2.0,22.0
8.0,4.0,40.0
10.0,1.0,52.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
