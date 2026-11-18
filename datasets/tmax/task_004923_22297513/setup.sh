#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender_id,receiver_id,amount,timestamp
tx001,userA,userB,10.0,1672531200
tx002,userA,userC,20.0,1672531260
tx003,userA,userD,100.0,1672531320
tx004,userB,userA,50.0,1672531380
tx005,userB,userE,60.0,1672531440
tx006,userB,userF,200.0,1672531500
tx007,userA,userE,5.0,1672531560
EOF

    chmod -R 777 /home/user
