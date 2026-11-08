#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/environments/prod
    mkdir -p /home/user/environments/staging/nested
    mkdir -p /home/user/final_backup

    # Create mock configs
    mkdir -p /tmp/mock_configs/prod /tmp/mock_configs/staging
    cat << 'EOF' > /tmp/mock_configs/prod/app1.conf
server_port=8080
db_host=old-db.legacy.local
db_port=5432
EOF

    cat << 'EOF' > /tmp/mock_configs/prod/app2.conf
server_port=8081
db_host=old-db.legacy.local
db_port=5432
EOF

    cat << 'EOF' > /tmp/mock_configs/staging/worker.conf
worker_threads=4
db_host=old-db.legacy.local
cache_host=redis.local
EOF

    cat << 'EOF' > /tmp/mock_configs/staging/dashboard.conf
ui_mode=dark
db_host=old-db.legacy.local
EOF

    # Zip them up
    cd /tmp/mock_configs/prod && zip -r /home/user/environments/prod/prod_configs.zip ./*
    cd /tmp/mock_configs/staging && zip -r /home/user/environments/staging/nested/staging_configs.zip ./*

    # Cleanup temp
    rm -rf /tmp/mock_configs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
