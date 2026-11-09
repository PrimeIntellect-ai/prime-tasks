#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
ID,f1,f2,f3,f4,f5,f6
TARGET,1.0,2.0,3.0,4.0,5.0,6.0
A,1.0,2.1,3.0,3.9,5.0,6.0
B,,2.0,3.0,4.0,5.0,6.0
C,100.0,100.0,3.0,4.0,5.0,6.0
D,1.0,2.0,3.0,4.0,4.0,6.0
E,1.0,2.0,3.0,4.0,1.0,1.0
F,-20.0,5.0,3.0,4.0,5.0,6.0
EOF

    chmod -R 777 /home/user
