#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/warehouses.csv
w_id,name,region
W001,Alpha,North
W002,Beta,North
W003,Gamma,East
W004,Delta,South
W005,Epsilon,West
W006,Zeta,Central
EOF

    cat << 'EOF' > /home/user/data/routes.csv
src_w_id,dst_w_id,distance,risk_score
W001,W002,10,2
W001,W004,50,5
W001,W006,100,9
W002,W003,20,4
W002,W005,15,3
W004,W005,10,1
W005,W006,20,1
W002,W006,10,8
W003,W006,30,2
EOF

    cat << 'EOF' > /home/user/data/inventory.csv
w_id,item_id,quantity
W001,ITEM-111,200
W003,ITEM-999,40
W005,ITEM-999,10
W006,ITEM-999,150
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
