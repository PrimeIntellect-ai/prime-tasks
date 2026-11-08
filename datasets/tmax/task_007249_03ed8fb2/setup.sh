#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
alpha,beta
2.0,10.0
4.0,12.0
NA,9.0
6.0,14.0
8.0,16.0
10.0,18.0
invalid,20.0
100.0,22.0
EOF

    chmod -R 777 /home/user
