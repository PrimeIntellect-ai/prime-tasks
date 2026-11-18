#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,name
1,Core_System
2,Auth_Module
3,DB_Driver
4,Logger
5,Crypto_Lib
6,Network_Stack
7,UI_Component
8,Standalone_Tool
EOF

    cat << 'EOF' > /home/user/edges.csv
parent_id,child_id
1,2
1,3
2,4
2,5
3,4
3,6
7,1
EOF

    chmod 644 /home/user/nodes.csv /home/user/edges.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
