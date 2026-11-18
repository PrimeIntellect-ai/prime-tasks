#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,feature_x,target
1,45,0
2,-999,1
3,60,1
4,55,1
5,-999,0
6,70,0
7,20,0
8,40,1
9,80,1
10,-999,1
EOF

    chmod -R 777 /home/user
