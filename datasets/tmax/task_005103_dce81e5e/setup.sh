#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/input.csv
x1,x2,y
1.0,2.0,7.0
2.0,NaN,12.0
3.0,4.0,15.0
4.0,6.0,20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
