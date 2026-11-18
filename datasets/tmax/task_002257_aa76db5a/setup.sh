#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,name
10,StartNode
15,IntermediateA
20,IntermediateB
30,IntermediateC
42,EndNode
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,cost,version
10,15,5,1
15,42,10,1
10,20,2,1
20,30,1,1
30,42,1,1
20,42,1,2
20,42,5,1
10,42,100,1
EOF

    cat << 'EOF' > /home/user/tombstones.csv
src,dst,version
20,42,3
10,42,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
