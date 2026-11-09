#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/network_data

    cat << 'EOF' > /home/user/network_data/nodes.csv
node_id,node_name,type
101,Alpha,Ingress
102,Bravo,Router
103,Charlie,Router
104,Delta,Switch
105,Echo,Switch
106,Foxtrot,Router
107,Omega,Egress
EOF

    cat << 'EOF' > /home/user/network_data/edges.csv
source_id,target_id,cost
101,102,10
101,103,15
102,104,12
103,104,2
104,105,5
105,107,8
103,105,20
105,106,3
106,107,4
999,106,5
104,888,10
EOF

    chmod -R 777 /home/user
