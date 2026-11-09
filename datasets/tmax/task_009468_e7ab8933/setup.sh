#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/edges.csv
source,target,weight
A,B,4
A,C,2
B,C,5
B,D,10
C,E,3
E,D,4
D,Z,11
E,Z,20
A,F,1
F,G,2
G,H,3
H,Z,15
C,F,1
F,Z,25
G,Z,8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
