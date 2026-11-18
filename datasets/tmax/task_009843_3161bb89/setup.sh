#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/analysis

    cat << 'EOF' > /home/user/data/users.csv
user_id,f1,f2,f3,f4
U1,0.5,1.2,3.4,0.1
U2,0.6,1.1,3.3,0.2
U3,5.5,2.0,1.1,4.4
U4,0.5,1.2,3.4,0.1,extra_col
U5,0.4,1.3,3.5,0.0
invalid_id,1.0,1.0,1.0,1.0
U6,abc,1.1,3.3,0.2
U7,1.0,1.0,1.0,1.0
U8,0.5,1.2,10.0,0.1
U9,0.5
U10,0.45,1.25,3.35,0.15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
