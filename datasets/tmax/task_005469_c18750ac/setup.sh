#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.csv
tx_id,amount
T01,100.50
T02,200.00
T03,300.00
T04,400.00
T05,500.50
T06,600.00
T07,700.00
T08,800.00
T09,900.00
T10,1000.00
EOF

    cat << 'EOF' > /home/user/locks.csv
waiting_tx,holding_tx
T01,T02
T02,T03
T03,T01
T04,T05
T05,T06
T06,T04
T07,T08
T08,T09
T09,T10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
