#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
6,Frank
7,Grace
EOF

    cat << 'EOF' > /home/user/friends.csv
source_id,target_id
1,2
1,3
1,4
2,1
3,2
3,4
3,5
3,6
4,1
4,5
5,6
5,7
5,1
6,7
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,user_id,amount,timestamp
t1,1,45.0,2023-01-01T10:00:00Z
t2,1,120.0,2023-01-02T10:00:00Z
t3,2,30.0,2023-01-01T11:00:00Z
t4,3,200.0,2023-01-03T10:00:00Z
t5,3,150.0,2023-01-04T10:00:00Z
t6,4,80.0,2023-01-01T12:00:00Z
t7,5,80.0,2023-01-02T12:00:00Z
t8,6,300.0,2023-01-05T10:00:00Z
t9,7,60.0,2023-01-06T10:00:00Z
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
