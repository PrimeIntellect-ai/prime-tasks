#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.csv
tx_id,resource_id,status
1,A,GRANTED
2,A,WAITING
3,A,WAITING
4,B,GRANTED
1,B,WAITING
5,B,WAITING
6,C,GRANTED
4,C,WAITING
7,D,WAITING
EOF

    chmod -R 777 /home/user
