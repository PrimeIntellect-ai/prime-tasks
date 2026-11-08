#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/staging /home/user/workspace

    cat << 'EOF' > /home/user/staging/sales_wide.csv
ID,Region,Q1,Q2,Q3,Q4
101,North,150,200,-50,300
102,South,100,150,200,250
103,East,-100,50,50,50
104,West,500,600,700,800
105,North,25,25,25,25
106,East,200,200,200,200
107,Central,10,10,-10,10
108,South,0,50,-20,100
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
