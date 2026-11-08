#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
user_id,region
U1,North
U2,South
U3,East
EOF

    cat << 'EOF' > /home/user/data/tx_batch1.csv
transaction_id,user_id,timestamp,amount
T1,U1,2023-01-01T10:00:00,10.0
T2,U1,2023-01-02T10:00:00,20.0
T4,U2,2023-01-01T11:00:00,50.0
T6,U3,2023-01-01T12:00:00,100.0
EOF

    cat << 'EOF' > /home/user/data/tx_batch2.csv
transaction_id,user_id,timestamp,amount
T2,U1,2023-01-02T10:00:00,20.0
T3,U1,2023-01-03T10:00:00,15.0
T4,U2,2023-01-01T11:00:00,50.0
T5,U2,2023-01-02T11:00:00,10.0
T7,U3,2023-01-02T12:00:00,200.0
T8,U3,2023-01-03T12:00:00,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
