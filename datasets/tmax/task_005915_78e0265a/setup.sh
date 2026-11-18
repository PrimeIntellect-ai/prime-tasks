#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/components.csv
1,Public
2,Internal
3,Encryption
4,Internal
5,PII
6,Internal
7,PII
8,Encryption
9,Public
10,PII
11,Public
12,Internal
13,PII
14,Internal
15,PII
EOF

    cat << 'EOF' > /home/user/data_flows.csv
1,2
2,3
3,4
4,5
1,6
6,7
9,8
8,10
9,6
11,12
12,13
12,8
8,15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
