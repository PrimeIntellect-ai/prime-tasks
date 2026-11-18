#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust toolchain
    apt-get install -y cargo rustc

    # Create directories and data
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/experiment_metrics.csv
id,feature_a,feature_b,target
1,10.0,10.0,21.0
2,10.0,20.0,31.0
,15.0,15.0,99.0
4.0,20.0,20.0,39.0
5,18.0,22.0,39.0
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
