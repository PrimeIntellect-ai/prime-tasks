#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sensors.csv
id,temperature,humidity
1,20.5,45.0
2,22.1,48.2
3,ERR,50.1
4,19.8,43.5
5,23.0,52.0
6,21.5,invalid
7,24.5,55.5
8,18.0,40.0
9,19.2,42.1
10,25.1,58.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
