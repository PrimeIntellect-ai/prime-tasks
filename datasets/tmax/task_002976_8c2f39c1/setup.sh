#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/waits.csv
waiting_trx,blocking_trx,resource
T100,T101,users
T101,T102,orders
T102,T100,inventory
T103,T104,audit_log
T104,T105,sessions
T106,T106,self_wait
T107,T108,cache
T108,T109,cache
T109,T107,cache
T110,T101,users
EOF

    chmod -R 777 /home/user
