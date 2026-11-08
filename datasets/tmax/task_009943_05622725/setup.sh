#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/accounts.csv
id,parent_id,name
1,,Root
2,1,Branch_A
3,1,Branch_B
4,2,Leaf_A1
5,3,Leaf_B1
6,5,Deep_Leaf
7,,Outside
EOF

    cat << 'EOF' > /home/user/transactions.csv
id,from_id,to_id,amount,ts
1,7,1,5000,2023-01-01 10:00:00
2,1,2,2000,2023-01-02 10:00:00
3,1,3,2000,2023-01-03 10:00:00
4,2,4,1500,2023-01-04 10:00:00
5,4,5,1000,2023-01-05 10:00:00
6,5,6,1200,2023-01-06 10:00:00
7,7,6,500,2023-01-07 10:00:00
EOF

    chmod -R 777 /home/user
