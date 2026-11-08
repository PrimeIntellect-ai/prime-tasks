#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
id,x,y
1,1.0,3.5
2,2.0,3.9
3,NaN,5.0
4,3.0,7.6
5,,2.0
6,4.0,12.3
7,5.0,NaN
8,abc,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
