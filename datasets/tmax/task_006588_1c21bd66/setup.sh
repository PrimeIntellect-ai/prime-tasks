#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_data/

    cat << 'EOF' > /home/user/raw_data/model_A.csv
id,condition,score,status
1,heat,0.85,SUCCESS
2,cold,0.12,SUCCESS
3,heat,1.50,SUCCESS
4,acid,-0.10,ERROR
5,acid,0.99,SUCCESS
EOF

    cat << 'EOF' > /home/user/raw_data/model_B.csv
id,condition,score,status
6,heat,0.65,SUCCESS
7,cold,0.88,SUCCESS
8,acid,0.45,SUCCESS
9,cold,0.50,ERROR
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
