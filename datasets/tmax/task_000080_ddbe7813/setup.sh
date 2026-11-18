#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/temperature.csv
1,30.0
5,34.0
11,28.0
15,30.0
EOF

    cat << 'EOF' > /home/user/state.csv
1,IDLE
6,ACTIVE
12,ERROR
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
