#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/predictions.csv
id,model_score,is_correct
1,0.75,1
2,0.72,0
3,0.81,1
4,0.79,1
5,0.65,0
6,0.70,1
7,0.799,0
8,0.80,0
9,0.73,1
10,0.77,1
11,0.74,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
