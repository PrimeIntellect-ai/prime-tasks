#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/features.csv
2.0,4.0,6.0
4.0,2.0,8.0
6.0,10.0,14.0
8.0,12.0,16.0
10.0,14.0,20.0
EOF

    chmod -R 777 /home/user
