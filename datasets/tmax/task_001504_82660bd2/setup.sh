#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/edges.csv
source,target,weight
U1,U2,500
U2,U3,200
U1,U3,300
U3,U1,100
U4,U1,150
U5,U5,50
U6,U2,100
U3,U4,150
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
