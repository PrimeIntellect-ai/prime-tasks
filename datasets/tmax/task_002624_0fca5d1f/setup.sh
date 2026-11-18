#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/input.csv
f1,f2,f3,target
1.0,2.0,3.0,10.0
4.0,5.0,6.0,20.0
7.0,8.0,10.0,30.0
1.5,2.5,3.5,12.0
NaN,1.0,2.0,5.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
