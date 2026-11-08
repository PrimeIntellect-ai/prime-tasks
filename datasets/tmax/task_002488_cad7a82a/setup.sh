#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
id,feature_a,target_val,feature_b
1,0.55,100,0.11
2,0.66,101,0.22
3,0.77,102.0,0.33
4,0.11,NaN,0.44
5,0.22,,0.55
6,0.33,-50,0.66
7,0.44,a10,0.77
8,0.55,200,0.88
9,0.12,0,0.99
10,0.45,-,0.12
11,0.99,3.14,0.15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
