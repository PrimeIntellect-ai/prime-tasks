#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,cpu,memory,latency
1,10.0,16.0,12.0
2,20.0,16.5,24.0
3,30.0,15.5,28.0
4,40.0,17.0,45.0
5,50.0,16.2,51.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
