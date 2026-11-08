#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,name,status
1,Alpha,ACTIVE
2,Bravo,ACTIVE
3,Charlie,INACTIVE
4,Delta,ACTIVE
5,Echo,ACTIVE
6,Foxtrot,ACTIVE
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,cost,capacity
1,2,10,100
1,3,5,50
2,4,20,200
3,4,10,100
4,5,5,150
5,6,15,100
2,5,30,50
1,6,100,10
EOF

    chmod -R 777 /home/user
