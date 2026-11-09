#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network.csv
source,target,weight,timestamp
A,B,10,1
A,C,5,2
B,D,8,3
C,D,15,4
D,E,2,5
A,F,20,6
F,G,1,7
A,H,10,8
H,I,12,9
A,J,5,10
EOF

    chmod -R 777 /home/user
