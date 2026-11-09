#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/batch1.csv
tx_id,timestamp,user_id,amount
T001,2023-10-01T10:00:00Z,U1,100.0
T002,2023-10-01T11:00:00Z,U2,150.0
T003,2023-10-02T09:00:00Z,U1,120.0
EOF

    cat << 'EOF' > /home/user/raw_data/batch2.csv
tx_id,timestamp,user_id,amount
T003,2023-10-02T08:00:00Z,U1,100.0
T004,2023-10-02T10:00:00Z,U3,400.0
EOF

    cat << 'EOF' > /home/user/raw_data/batch2_retry.csv
tx_id,timestamp,user_id,amount
T002,2023-10-01T12:00:00Z,U2,150.0
T003,2023-10-02T10:00:00Z,U1,120.0
T005,2023-10-03T11:00:00Z,U4,260.0
EOF

    chmod -R 777 /home/user
