#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph_edges.csv
u,v,cost
SYS_00,SYS_01,2
SYS_00,SYS_02,5
SYS_01,SYS_03,1
SYS_01,SYS_04,7
SYS_02,SYS_04,3
SYS_03,SYS_05,2
SYS_05,SYS_06,1
SYS_04,SYS_07,2
SYS_00,SYS_08,12
SYS_06,SYS_09,2
SYS_09,SYS_10,1
SYS_05,SYS_02,8
SYS_07,SYS_08,5
EOF

    chmod -R 777 /home/user
