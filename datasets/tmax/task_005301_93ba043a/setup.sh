#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network.csv
source,target,time,cost
A,B,5,10
A,C,10,5
B,D,5,20
C,D,15,5
A,D,30,2
B,E,10,10
E,D,5,10
EOF

    chmod -R 777 /home/user
