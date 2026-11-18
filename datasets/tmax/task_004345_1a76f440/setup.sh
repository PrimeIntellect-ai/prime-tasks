#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_type
A,Warehouse
B,Hub
C,Store
D,Hub
E,Store
F,Factory
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,cost,rel
A,B,10,CONNECTED_TO
A,C,50,CONNECTED_TO
B,C,15,CONNECTED_TO
B,D,5,DEPENDS_ON
D,E,10,CONNECTED_TO
A,E,5,INCOMPATIBLE_WITH
F,A,20,CONNECTED_TO
X,Y,10,CONNECTED_TO
Y,Z,15,DEPENDS_ON
A,W,5,CONNECTED_TO
EOF

    cat << 'EOF' > /home/user/queries.csv
start,end
A,C
A,E
B,E
F,C
A,F
EOF

    chmod -R 777 /home/user
