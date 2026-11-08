#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,group
1,A
2,B
3,A
4,B
5,A
6,B
7,A
8,B
9,A
10,B
EOF

    cat << 'EOF' > /home/user/transactions.csv
user_id,amount
1,100.5
2,210.0
3,115.2
4,250.5
5,95.0
6,300.0
7,105.0
8,220.5
9,110.0
10,240.0
EOF

    chmod -R 777 /home/user
