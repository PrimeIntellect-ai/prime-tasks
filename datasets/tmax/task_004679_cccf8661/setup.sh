#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
1,2
2,3
3,1
4,5
5,6
6,4
7,8
8,9
10,11
11,12
12,10
13,10
14,13
15,15
16,17
EOF

    chmod -R 777 /home/user
