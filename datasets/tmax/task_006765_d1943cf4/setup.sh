#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
tx_id,source_acc,target_acc,amount,timestamp
T1,ACC_001,ACC_002,100,2023-01-01T10:00:00Z
T2,ACC_002,ACC_003,100,2023-01-01T10:05:00Z
T3,ACC_003,ACC_001,100,2023-01-01T10:10:00Z
T4,ACC_001,ACC_004,500,2023-01-01T11:00:00Z
T5,ACC_004,ACC_005,500,2023-01-01T11:05:00Z
T6,ACC_005,ACC_001,500,2023-01-01T11:10:00Z
T7,ACC_004,ACC_006,200,2023-01-01T12:00:00Z
T8,ACC_006,ACC_007,200,2023-01-01T12:05:00Z
T9,ACC_007,ACC_008,200,2023-01-01T12:10:00Z
T10,ACC_008,ACC_004,200,2023-01-01T12:15:00Z
T11,ACC_009,ACC_010,50,2023-01-01T13:00:00Z
EOF

    chmod -R 777 /home/user
