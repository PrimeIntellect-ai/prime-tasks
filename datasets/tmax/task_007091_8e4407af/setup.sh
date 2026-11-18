#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network_edges.csv
NODE_001,NODE_100,1.0
NODE_100,NODE_200,1.0
NODE_200,NODE_300,1.0
NODE_300,NODE_999,1.0
NODE_001,NODE_999,0.0,CROSS_JOIN_ERROR
NODE_100,NODE_999,0.0,CROSS_JOIN_ERROR
NODE_001,NODE_050,1.0
NODE_050,NODE_075,1.0
NODE_075,NODE_100,1.0
EOF
    chmod 644 /home/user/network_edges.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
