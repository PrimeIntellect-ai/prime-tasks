#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
tx_id,resource_id,start_ts,end_ts
1,100,10,20
2,100,15,25
3,100,22,30
4,101,5,10
5,101,10,15
6,101,10,12
7,102,1,100
8,102,2,3
9,102,4,5
EOF

    chmod -R 777 /home/user
