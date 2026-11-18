#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest networkx pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network.csv
source,target,weight
A,B,2
A,C,5
B,C,1
B,D,4
C,D,1
D,E,3
C,Node_Z,8
E,Node_Z,2
C,F,1
C,G,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
