#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,label,properties,updated_at
U1,User,"{}",1
U2,User,"{}",1
U3,User,"{}",1
U4,User,"{}",1
U5,User,"{}",1
P1,Product,"{""category"": ""laptop""}",1
P2,Product,"{""category"": ""laptop""}",1
P2,Product,"{""category"": ""tablet""}",2
P3,Product,"{""category"": ""laptop""}",1
P4,Product,"{""category"": ""laptop""}",1
P5,Product,"{""category"": ""laptop""}",1
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,rel_type,updated_at
U1,P1,PURCHASED,1
U1,P3,PURCHASED,1
U1,P4,PURCHASED,1
U1,P5,PURCHASED,1
U4,P1,PURCHASED,1
U4,P3,PURCHASED,1
U4,P4,PURCHASED,1
U4,P5,PURCHASED,1
U4,P5,PURCHASED,2
U2,P1,PURCHASED,1
U2,P3,PURCHASED,1
U2,P2,PURCHASED,1
U3,P4,PURCHASED,1
U5,P1,PURCHASED,1
U5,P3,PURCHASED,1
U5,P4,PURCHASED,1
EOF

    chmod -R 777 /home/user
