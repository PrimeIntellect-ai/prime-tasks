#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.txt
1 1620000000 U1 U2 100
2 1620000005 U1 U3 500
3 1620000010 U1 U2 200
4 1620000015 U1 U4 600
5 1620000020 U1 U5 100
6 1620000025 U2 U1 5000
7 1620000030 U2 U3 50
8 1620000035 U3 U1 400
9 1620000040 U3 U2 400
10 1620000045 U3 U4 400
11 1620000050 U3 U5 400
12 1620000055 U4 U1 1000
13 1620000060 U5 U1 100
EOF

    chmod -R 777 /home/user
