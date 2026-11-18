#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/accounts.csv
account_id,account_name
1,Alice_Corp
2,Bob_LLC
3,Charlie_Inc
4,Delta_Co
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,src_id,dst_id,amount,tx_date
101,1,2,2000,2023-01-01
102,1,3,1500,2023-01-02
103,1,4,2000,2023-01-03
104,2,3,4000,2023-01-01
105,2,4,1500,2023-01-05
106,3,1,1000,2023-01-02
107,3,2,6000,2023-01-04
108,4,1,3000,2023-01-01
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
