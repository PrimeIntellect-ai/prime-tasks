#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_type,name
101,PERSON,Alice
102,PERSON,Bob
103,CORP,CharlieCorp
104,PERSON,David
105,CORP,EveLLC
106,PERSON,Frank
EOF

    cat << 'EOF' > /home/user/edges.csv
src_id,dst_id,rel_type,amount
101,102,TRANSFER,1500
102,103,TRANSFER,1200
103,101,TRANSFER,2000
103,104,TRANSFER,5000
104,105,TRANSFER,1100
105,103,TRANSFER,800
104,101,TRANSFER,1500
101,103,TRANSFER,3000
106,102,TRANSFER,4000
102,106,TRANSFER,5000
106,101,PAYMENT,2000
101,106,TRANSFER,1500
EOF

    chmod -R 777 /home/user
