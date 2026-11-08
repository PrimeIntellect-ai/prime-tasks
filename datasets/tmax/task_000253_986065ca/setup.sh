#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transaction_locks.csv
TX_100,RES_A,GRANTED
TX_200,RES_A,WAITING
TX_200,RES_B,GRANTED
TX_300,RES_B,WAITING
TX_300,RES_C,GRANTED
TX_994,RES_C,WAITING
TX_994,RES_X,GRANTED
TX_881,RES_X,WAITING
TX_881,RES_Y,GRANTED
TX_772,RES_Y,WAITING
TX_772,RES_Z,GRANTED
TX_994,RES_Z,WAITING
EOF
    chmod 644 /home/user/transaction_locks.csv

    chmod -R 777 /home/user
    # fix 644 permissions for the test
    chmod 644 /home/user/transaction_locks.csv
