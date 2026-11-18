#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/observations.csv
x,y,v
0.1,0.1,1.0
0.2,0.2,5.0
0.8,0.8,2.0
0.9,0.9,2.0
0.1,0.6,1.0
0.2,0.7,1.0
0.6,0.1,1.0
0.7,0.2,1.0
0.3,0.1,1.0
0.1,0.3,1.0
0.4,0.4,1.0
0.45,0.45,1.0
EOF
    chmod 644 /home/user/observations.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
