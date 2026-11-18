#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest networkx pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/edges.csv
src,dst,weight
A,B,1.0
B,C,2.0
C,D,1.5
D,A,0.5
E,F,3.0
G,H,1.0
H,I,1.0
X,Y,5.0
Y,Z,2.0
Z,X,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
