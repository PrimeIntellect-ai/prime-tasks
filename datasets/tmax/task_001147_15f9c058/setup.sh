#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/logistics_graph/data
    mkdir -p /home/user/logistics_graph/output

    # Create nodes.csv
    cat << 'EOF' > /home/user/logistics_graph/data/nodes.csv
node_id,node_name
A,Alpha
B,Bravo
C,Charlie
D,Delta
E,Echo
F,Foxtrot
EOF

    # Create edges.csv
    cat << 'EOF' > /home/user/logistics_graph/data/edges.csv
source_id,target_id,distance,cost
A,B,10.0,5.0
B,C,20.0,10.0
A,C,50.0,2.0
C,D,15.0,8.0
B,D,40.0,20.0
D,E,5.0,2.0
E,F,10.0,5.0
C,F,35.0,20.0
EOF

    # Create queries.csv
    cat << 'EOF' > /home/user/logistics_graph/data/queries.csv
source_id,target_id
A,D
A,C
A,F
E,A
B,E
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
