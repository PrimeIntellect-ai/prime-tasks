#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,username,region
1,alice,EU
2,bob,EU
3,charlie,EU
4,david,US
5,eve,US
6,frank,US
7,grace,US
8,heidi,EU
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender_id,receiver_id,amount
t1,1,2,100.0
t2,2,3,50.0
t3,1,3,200.0
t4,4,5,300.0
t5,6,4,150.0
t6,5,6,120.0
t7,7,4,500.0
t8,1,8,300.0
t9,8,2,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
