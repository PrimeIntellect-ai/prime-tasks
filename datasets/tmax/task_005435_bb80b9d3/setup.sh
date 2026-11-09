#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/entity_info.csv
alpha_id,handle,profile_score
101,Alice,0.9
102,Bob,0.8
103,Charlie,0.7
104,Diana,0.6
105,Eve,0.5
EOF

    cat << 'EOF' > /home/user/data/events.csv
ref_hash,col_s,col_r,val
tx1,101,102,100
tx2,101,103,60
tx3,101,104,200
tx4,102,103,80
tx5,102,104,90
tx6,103,104,51
tx7,104,105,100
tx8,101,101,1000
tx9,101,102,120
tx10,105,101,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
