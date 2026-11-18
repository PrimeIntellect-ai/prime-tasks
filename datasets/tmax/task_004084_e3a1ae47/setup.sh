#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/accounts.csv
account_id,status,type
1,ACTIVE,Checking
2,ACTIVE,Savings
3,INACTIVE,Checking
4,ACTIVE,Checking
5,ACTIVE,Savings
6,ACTIVE,Checking
7,ACTIVE,Checking
EOF

    cat << 'EOF' > /home/user/transactions.csv
source,target,amount
1,2,600.0
1,4,700.0
1,5,800.0
2,4,900.0
2,6,100.0
3,1,1000.0
4,1,600.0
4,5,600.0
4,6,600.0
7,1,800.0
7,2,800.0
7,4,800.0
7,5,800.0
EOF

    chmod -R 777 /home/user
