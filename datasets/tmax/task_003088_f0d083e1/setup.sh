#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset_stats.csv
dataset_id,prior_clean,likelihood_clean,likelihood_corrupt
ds_001,0.90,0.85,0.10
ds_002,0.50,0.10,0.95
ds_003,0.99,0.99,0.01
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
