#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_nodes.csv
id,label
1,Server
2,Router
3,Switch
4,Database
5,Firewall
EOF

    cat << 'EOF' > /home/user/backup_edges.csv
source,target,type
1,3,CONNECTED_TO
2,3,CONNECTED_TO
4,3,CONNECTED_TO
5,2,ROUTED_THROUGH
5,1,SECURES
1,4,QUERIES
EOF

    chmod -R 777 /home/user
