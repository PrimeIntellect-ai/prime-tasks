#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/entities.csv
id,name,industry
10,Apex_Holdings,Holding
11,Bravo_Corp,Manufacturing
12,Charlie_Inc,Logistics
13,Delta_LLC,Retail
14,Echo_Group,Tech
15,Foxtrot_Ltd,Services
16,Zeta_Retail,Retail
17,Ghost_Corp,Shell
EOF

    cat << 'EOF' > /home/user/data/relationships.csv
parent_id,child_id,relationship_type,ownership_percentage
10,11,owns,100
10,12,owns,80
10,17,owns,40
11,13,owns,60
12,14,owns,55
13,16,owns,51
14,15,owns,90
15,16,owns,100
17,16,owns,100
10,14,supplies,100
EOF

    chmod -R 777 /home/user
