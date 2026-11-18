#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
source,target,amount,timestamp
A,B,100,1
A,B,150,2
C,B,200,3
D,B,50,4
E,B,300,5
F,B,10,6
B,C,500,7
A,C,400,8
C,A,50,9
C,A,60,10
E,F,100,11
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
