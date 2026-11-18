#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/waits.csv
tx_id,waiting_for_tx_id
1,2
2,3
3,1
4,5
5,6
7,8
8,9
9,7
10,2
11,11
12,13
13,14
EOF

    chmod -R 777 /home/user
