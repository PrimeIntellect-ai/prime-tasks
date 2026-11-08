#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
user_id,transaction_id,amount
A,9007199254740993,10.5
B,,20.0
C,9007199254740995,15.2
D,9007199254741001,8.0
E,,100.0
EOF

    chmod -R 777 /home/user
