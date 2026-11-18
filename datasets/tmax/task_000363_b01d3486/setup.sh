#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/vectors.csv
id,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10
A,1,2,-1,0,3,0,0,1,-1,2
B,2,-1,0,1,0,0,0,0,0,0
C,0,0,0,0,0,1,-1,2,0,0
D,-1,-2,1,0,-3,0,0,-1,1,-2
E,0,0,0,0,0,1,1,0,0,0
F,1,,3,4,5,6,7,8,9,0
G,2,4,-2,0,6,0,0,2,-2,4
H,1,1,1,1,1,1,1,1,1,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
