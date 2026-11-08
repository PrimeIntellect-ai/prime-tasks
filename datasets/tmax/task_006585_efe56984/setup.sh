#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/experiments.csv
exp_id,validation_score,test_score
e1,0.9500,0.9500
e2,0.9100,0.9105
e3,0.8800,0.8800
e4,0.7000,0.6999
EOF

    cat << 'EOF' > /home/user/data/embeddings.csv
exp_id,v1,v2,v3
e1,0.1,0.1,0.1
e2,0.4,0.6,0.5
e3,0.9,0.9,0.9
e4,0.2,0.8,0.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
