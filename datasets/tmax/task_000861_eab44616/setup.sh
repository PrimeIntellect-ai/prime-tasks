#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/transfers.csv
tx_id,sender,receiver,amount
1,U1,U2,100
2,U2,U3,150
3,U3,U1,200
4,U4,U5,300
5,U5,U6,50
6,U6,U4,500
7,U1,U7,1000
8,U8,U1,2000
9,U1,U9,5000
10,U4,U2,9999
11,U3,U4,8888
12,U9,U10,10
13,U10,U11,20
14,U11,U9,30
15,U11,U12,50000
EOF

    chmod -R 777 /home/user
