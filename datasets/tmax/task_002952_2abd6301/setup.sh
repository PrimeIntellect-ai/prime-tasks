#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
ID,Tags,Value
1,alpha|beta,10
2,alpha,
3,gamma|beta,15
4,alpha,5
5,gamma,
6,delta,0
7,delta|alpha,20
8,beta,
EOF

    chmod -R 777 /home/user
