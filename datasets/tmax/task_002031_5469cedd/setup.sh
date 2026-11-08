#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.graph
Tx10 :ACQUIRED Lock1
Tx11 :ACQUIRED Lock2
Tx12 :ACQUIRED Lock3
Tx13 :ACQUIRED Lock4
Tx10 :WAIT_FOR Tx11
Tx11 :KNOWS Tx15
Tx11 :WAIT_FOR Tx12
Tx12 :WAIT_FOR Tx13
Tx13 :WAIT_FOR Tx11
Tx99 :WAIT_FOR Tx100
Tx100 :WAIT_FOR Tx101
EOF

    chmod -R 777 /home/user
