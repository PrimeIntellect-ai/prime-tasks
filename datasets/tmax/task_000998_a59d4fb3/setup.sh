#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/stations.csv
s_id,s_name,zone
1,Alpha Hub,North
2,Beta Station,North
3,Gamma Relay,East
4,Delta Point,South
5,Omega Terminus,West
EOF

    cat << 'EOF' > /home/user/routes.csv
r_id,src_node,dst_node,travel_time,op_status
101,1,2,10,ACTIVE
102,1,3,15,ACTIVE
103,2,4,20,ACTIVE
104,3,4,5,ACTIVE
105,4,5,10,ACTIVE
106,1,5,5,INACTIVE
107,3,5,50,ACTIVE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
