#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,type
10,User
11,Order
12,Product
13,User
14,Order
15,Product
16,Order
17,Product
18,User
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,relation
10,11,BUYS
11,12,CONTAINS
13,14,BUYS
14,15,CONTAINS
13,16,BUYS
16,17,CONTAINS
18,16,BUYS
EOF

    chmod -R 777 /home/user
