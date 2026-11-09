#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create data directory and logs.csv
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/logs.csv
id,group_id,content
1,100,XxYyZz
2,,XyzXyzXyz
3,200,hello world
4,,zzZZzz
5,105,xYxYxYxY
EOF

    # Create the Rust project
    cd /home/user
    cargo new log_pipeline

    # Ensure correct permissions
    chmod -R 777 /home/user
