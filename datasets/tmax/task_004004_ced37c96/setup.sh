#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/graph_data/

    cat << 'EOF' > /home/user/graph_data/nodes.csv
node_id,label,weight
U1,User,10
U2,User,20
U3,User,15
U4,User,25
I1,Item,50
I2,Item,30
I3,Item,70
I4,Item,45
I5,Item,10
C1,Category,0
C2,Category,0
EOF

    cat << 'EOF' > /home/user/graph_data/edges.csv
source_id,target_id,rel_type
U1,I1,PURCHASED
U1,I2,VIEWED
U2,I3,PURCHASED
U3,I1,PURCHASED
U4,I4,PURCHASED
U2,I5,PURCHASED
U1,I4,PURCHASED
I1,C1,BELONGS_TO
I2,C1,BELONGS_TO
I3,C2,BELONGS_TO
I4,C2,BELONGS_TO
I5,C1,BELONGS_TO
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
