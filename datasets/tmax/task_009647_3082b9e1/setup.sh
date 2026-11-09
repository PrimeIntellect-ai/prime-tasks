#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/nodes.csv
node_id,label,name
U-007,Person,James Bond
U-008,Person,Alec Trevelyan
U-009,Person,Q
L-101,Location,London
L-102,Location,MI6 HQ
V-999,Vehicle,Aston Martin DB5
E-001,Enemy,Ernst Stavro Blofeld
E-002,Enemy,Jaws
U-010,Person,M
L-103,Location,Spectre Island
EOF

    cat << 'EOF' > /home/user/data/edges.csv
src_id,dst_id,relation,weight
U-007,L-101,VISITED,5.0
U-007,U-008,KNOWS,1.2
U-008,L-101,VISITED,3.1
U-007,U-009,REPORTS_TO,1.0
U-009,L-102,WORKS_AT,10.0
U-007,V-999,DRIVES,9.5
E-001,L-103,OWNS,100.0
E-002,E-001,WORKS_FOR,2.5
U-007,E-001,FIGHTS,8.8
U-010,L-102,WORKS_AT,10.0
EOF

    chmod -R 777 /home/user
