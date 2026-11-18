#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locks.csv
waiting_txn,holding_txn,wait_time_ms
T10,T20,10
T20,T30,20
T30,T50,50
T10,T15,30
T15,T50,30
T15,T25,10
T25,T50,15
T10,T99,5
T99,T15,10
T99,T50,100
T20,T10,50
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
