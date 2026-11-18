#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/wait_for_graph.csv
waiting_txn,holding_txn
TXN-105,TXN-209
TXN-209,TXN-314
TXN-314,TXN-881
TXN-881,TXN-402
TXN-402,TXN-550
TXN-550,TXN-209
TXN-600,TXN-105
TXN-700,TXN-600
TXN-402,TXN-999
EOF

    chmod -R 777 /home/user
