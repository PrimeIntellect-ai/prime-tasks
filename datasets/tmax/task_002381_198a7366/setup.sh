#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_label,attr1,attr2
U1,User,Alice,28
U2,User,Bob,35
U3,User,Charlie,42
P1,Product,Laptop,1200
P2,Product,Mouse,25
P3,Product,Desk,300
P4,Product,Smartphone,800
C1,Category,Electronics,Gadgets
C2,Category,Furniture,Home
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,rel_type,rel_attr
U1,P1,PURCHASED,2023-10-01
U1,P2,PURCHASED,2023-10-05
U2,P1,PURCHASED,2023-10-02
U2,P3,PURCHASED,2023-10-03
U3,P4,PURCHASED,2023-10-10
P1,C1,BELONGS_TO,
P2,C1,BELONGS_TO,
P3,C2,BELONGS_TO,
P4,C1,BELONGS_TO,
EOF

    chmod -R 777 /home/user
