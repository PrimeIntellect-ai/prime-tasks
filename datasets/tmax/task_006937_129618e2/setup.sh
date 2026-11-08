#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
id,name
1,Alice
2,Bob
3,Charlie
4,David
5,Eve
6,Frank
7,Grace
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender_id,receiver_id,amount
101,1,2,600
102,2,3,700
103,3,1,800
104,3,4,900
105,4,1,1000
106,2,4,100
107,5,6,600
108,6,7,600
109,7,5,400
110,1,3,600
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
