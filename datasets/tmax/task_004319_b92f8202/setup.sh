#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    mkdir -p /home/user/logistics

    cat << 'EOF' > /home/user/logistics/nodes.csv
node_id,name,is_active
1,Alpha,True
2,Bravo,False
3,Charlie,True
4,Delta,True
5,Echo,True
6,Foxtrot,True
7,Kilo,True
EOF

    cat << 'EOF' > /home/user/logistics/edges.csv
source,target,weight,edge_type
1,2,2,standard
2,7,3,standard
1,3,4,standard
3,7,2,maintenance
1,4,3,standard
4,5,2,standard
5,7,4,standard
1,6,1,standard
6,7,20,standard
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
