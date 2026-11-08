#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_name
1,Alpha
2,Bravo
3,Charlie
4,Delta
5,Echo
6,Foxtrot
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,weight,is_stale
1,2,10,0
1,3,15,0
2,4,20,0
3,4,5,0
4,5,10,0
5,6,5,0
1,6,100,1
2,5,5,1
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
