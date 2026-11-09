#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_edges.csv
source,target,latency
DC1,DC2,10
DC1,DC3,20
DC2,DC3,5
DC2,DC4,15
DC3,DC4,8
DC3,DC5,30
DC4,DC5,10
DC1,DC5,45
DC2,DC6,50
DC5,DC6,5
EOF

    cat << 'EOF' > /home/user/routes_to_calc.csv
DC1,DC4
DC1,DC5
DC2,DC6
DC3,DC6
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
