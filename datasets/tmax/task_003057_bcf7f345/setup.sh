#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/experiments.csv
A,1.0,2.0,0.5,0.1,0.2,0.4,0.7,1,1
A,0.5,0.5,0.5,1.0,1.0,1.0,1.5,1,1
A,1.0,0.0,0.0,1.0,1.0,1.0,0.0,1,1
B,2.0,1.0,0.0,0.5,0.5,0.0,1.5,2,2
B,0.0,0.0,1.0,0.0,0.0,0.3,0.3,2,2
B,1.0,1.0,1.0,0.3333,0.3333,0.3333,1.0,2,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
