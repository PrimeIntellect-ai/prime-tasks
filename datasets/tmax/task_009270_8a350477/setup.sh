#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /archive/remote_backup

    cat << 'EOF' > /home/user/data/points.csv
id,x,y,z
1,0.5,0.5,0.5
2,1.0,1.0,1.0
3,2.0,2.0,1.0
4,3.0,0.0,0.0
5,-2.0,-2.0,-1.0
6,0.0,0.0,0.0
7,5.0,5.0,5.0
8,0.0,4.0,3.0
9,10.0,0.0,0.0
EOF

    chmod 777 /archive/remote_backup
    chmod -R 777 /home/user
