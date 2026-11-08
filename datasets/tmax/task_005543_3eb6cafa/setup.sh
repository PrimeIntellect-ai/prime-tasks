#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.csv
tx_id,resource,state
200,users,HOLDING
201,orders,HOLDING
202,invoices,HOLDING
203,products,HOLDING
204,audit,HOLDING
205,sessions,HOLDING
200,audit,WAITING
201,users,WAITING
202,orders,WAITING
203,invoices,WAITING
204,sessions,WAITING
205,products,WAITING
206,users,WAITING
EOF

    chmod -R 777 /home/user
