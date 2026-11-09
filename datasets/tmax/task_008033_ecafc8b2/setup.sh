#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,cost
ROOT,10
A,20
B,25
C,15
D,5
E,30
F,50
UNREACHABLE,100
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,weight
ROOT,A,1
ROOT,B,1
ROOT,C,4
A,C,2
B,C,3
B,D,5
C,D,1
D,E,3
E,F,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
