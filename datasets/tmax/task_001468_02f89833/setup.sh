#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/accounts.csv
account_id,balance,status
A1,100,active
A2,200,active
A3,150,active
A4,300,active
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,from_account,to_account,amount,timestamp
T1,A1,A2,50,2023-10-01 10:05:12
T2,A2,A1,30,2023-10-01 10:05:45
T3,A3,A4,10,2023-10-01 11:00:00
T4,A4,A3,20,2023-10-01 11:02:00
T5,A1,A3,40,2023-10-01 10:05:30
T6,A5,A1,10,2023-10-01 12:00:00
T7,A2,A6,20,2023-10-01 12:05:00
EOF

    chmod -R 777 /home/user
