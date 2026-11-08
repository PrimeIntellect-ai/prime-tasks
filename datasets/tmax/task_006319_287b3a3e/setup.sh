#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev gawk diffutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
ALPHA,10.0,20.0,30.0
BETA,5.0,5.0,5.0
ALPHA,2.0,4.0,6.0
GAMMA,1.0,0.0,0.0
BETA,0.0,10.0,10.0
EOF

    chmod -R 777 /home/user
