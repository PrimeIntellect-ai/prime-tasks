#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/batch1.csv
dataset_id,trials,successes
alpha,10,5
beta,20,15
EOF

    cat << 'EOF' > /home/user/datasets/batch2.csv
dataset_id,trials,successes
alpha,15,10
gamma,50,45
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
