#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_type,base_value
A,hub,10
B,warehouse,20
C,hub,30
D,sorting,40
E,warehouse,50
F,hub,15
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,cost
A,B,5
A,C,15
A,F,2
F,B,10
B,C,8
C,D,10
B,E,25
D,E,5
F,E,40
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
