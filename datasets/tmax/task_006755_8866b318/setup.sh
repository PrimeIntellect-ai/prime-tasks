#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input/

    cat << 'EOF' > /home/user/input/matrices.csv
1,1.0,2.0,3.0,4.0
2,1.0000001,2.0,0.5,1.0
3,1e-8,1.0,1.0,1e-8
4,1000.0,0.001,0.001,1000.0
5,0.0,1.0,-1.0,0.0
6,0.333333333,1.0,1.0,3.0
7,3.14159,2.71828,1.61803,1.41421
8,10000000.0,0.0000001,0.0000001,10000000.0
9,1.000000001,1.0,1.0,1.0
10,-5.5,2.2,3.3,-1.32
EOF

    chmod -R 777 /home/user
