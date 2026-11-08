#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/accounts.csv
account_id,created_at,status
ACC1,2022-05-10,ACTIVE
ACC2,2023-06-15,ACTIVE
ACC3,2021-11-20,ACTIVE
ACC4,2023-02-10,SUSPENDED
ACC5,2023-08-01,ACTIVE
ACC6,2022-01-01,ACTIVE
ACC7,2023-05-05,ACTIVE
ACC8,2023-05-06,ACTIVE
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,src_account,dst_account,amount,tx_date
T1,ACC1,ACC2,4000.0,2023-09-01
T2,ACC2,ACC3,5000.0,2023-09-02
T3,ACC3,ACC1,1500.0,2023-09-03
T4,ACC3,ACC1,2000.0,2023-09-04
T5,ACC5,ACC6,6000.0,2023-09-05
T6,ACC6,ACC7,5000.0,2023-09-06
T7,ACC7,ACC5,1000.0,2023-09-07
T8,ACC2,ACC4,8000.0,2023-09-08
T9,ACC4,ACC1,3000.0,2023-09-09
T10,ACC1,ACC7,7000.0,2023-09-10
T11,ACC7,ACC8,5000.0,2023-09-11
T12,ACC8,ACC1,4000.0,2023-09-12
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
