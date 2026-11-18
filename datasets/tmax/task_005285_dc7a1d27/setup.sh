#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
user_id,product_id,timestamp
1,A,2023-01-01
1,B,2023-01-02
1,C,2023-01-03
2,A,2023-01-04
2,B,2023-01-05
2,D,2023-01-06
3,B,2023-01-07
3,C,2023-01-08
3,E,2023-01-09
4,A,2023-01-10
4,B,2023-01-11
4,C,2023-01-12
4,D,2023-01-13
5,A,2023-01-14
5,C,2023-01-15
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
