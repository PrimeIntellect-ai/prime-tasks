#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/purchases.csv
user_id,item_id,rating
U1,ITEM_001,4.5
U1,ITEM_002,5.0
U1,ITEM_003,3.0
U1,ITEM_004,2.0
U2,ITEM_001,4.0
U2,ITEM_002,4.5
U2,ITEM_003,3.5
U3,ITEM_001,5.0
U3,ITEM_002,4.0
U4,ITEM_001,4.0
U4,ITEM_011,4.0
U4,ITEM_012,4.0
U4,ITEM_013,4.0
U4,ITEM_014,4.0
U4,ITEM_015,4.0
U4,ITEM_016,4.0
U5,ITEM_001,6.0
U5,ITEM_002,
U6,ITEM_001,0.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
