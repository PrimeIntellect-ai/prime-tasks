#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_graph.csv
src,dst,weight
A,B,5
A,C,2
B,C,10
C,A,6
B,D,7
D,E,1
E,A,4
EOF

    chmod -R 777 /home/user
