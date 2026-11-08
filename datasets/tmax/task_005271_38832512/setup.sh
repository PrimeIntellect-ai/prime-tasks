#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
id,group,score
1,A,10
2,B,50
3,A,
4,A,20
5,C,100
6,A,30
7,A,
8,A,40
9,B,60
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
