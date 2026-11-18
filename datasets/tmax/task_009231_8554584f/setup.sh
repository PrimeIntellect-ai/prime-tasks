#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user/analytics
    cat << 'EOF' > /home/user/analytics/network.csv
A,B,5
A,C,6
B,C,2
D,A,15
D,B,1
E,F,5
G,H,12
H,A,10
H,B,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
