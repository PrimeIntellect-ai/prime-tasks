#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create nodes.csv
    cat << 'EOF' > /home/user/nodes.csv
node_id,status
START,active
END,active
A,active
B,inactive
C,active
D,active
E,active
F,active
EOF

    # Create edges.csv
    cat << 'EOF' > /home/user/edges.csv
source_node,target_node,cost
START,A,10
A,B,5
B,END,10
START,C,5
C,D,15
D,END,5
START,E,20
E,F,5
F,END,0
C,E,10
EOF

    chmod -R 777 /home/user
