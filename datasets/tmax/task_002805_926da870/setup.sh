#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.csv
tx_id,date,category,amount,customer_id
T001,2023-01-01,Electronics,250.50,C10
T002,2023-01-02,Books,15.99,C11
T003,2023-01-02,Electronics,899.00,C12
T004,2023-01-03,Clothing,45.00,C10
T005,2023-01-03,Books,22.50,C13
T006,2023-01-04,Electronics,120.00,C11
T007,2023-01-05,Clothing,75.00,C14
T008,2023-01-05,Books,12.00,C15
T009,2023-01-06,Electronics,50.00,C10
T010,2023-01-07,Books,5.99,C12
EOF

    cat << 'EOF' > /home/user/.expected_q1.txt
T003
T001
EOF

    cat << 'EOF' > /home/user/.expected_q2.txt
T008
T005
T002
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
