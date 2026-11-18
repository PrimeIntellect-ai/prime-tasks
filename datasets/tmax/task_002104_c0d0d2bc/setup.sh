#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/points.csv
id,x,y,z
1,2.0,1.0,1.0
2,-1.0,2.0,0.5
3,1.5,-0.5,2.0
bad_row,a,b,c
4,0.0,0.0,0.0
5,3.0,1.5,
6,2.0,-3.0,-1.0
7,0.5,0.5,0.5
EOF

    chmod -R 777 /home/user
