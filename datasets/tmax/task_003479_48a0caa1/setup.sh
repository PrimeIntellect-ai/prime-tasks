#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/config_manager/incoming
    cd /home/user/config_manager

    # Create base system.conf
    cat << 'EOF' > system.conf
DEBUG_MODE=false
TIMEOUT=30
MAX_USERS=100
CACHE_DIR=/var/cache
EOF

    # Update 1
    mkdir -p tmp1
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > tmp1/changes.wal
SET TIMEOUT=60
SET RETRIES=3
DELETE CACHE_DIR
EOF
    tar -czf incoming/update_1.tar.gz -C tmp1 changes.wal
    rm -rf tmp1

    # Update 2
    mkdir -p tmp2
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > tmp2/changes.wal
SET MAX_USERS=500
SET DEBUG_MODE=true
EOF
    tar -czf incoming/update_2.tar.gz -C tmp2 changes.wal
    rm -rf tmp2

    # Update 3
    mkdir -p tmp3
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > tmp3/changes.wal
DELETE RETRIES
SET LOG_LEVEL=info
EOF
    tar -czf incoming/update_3.tar.gz -C tmp3 changes.wal
    rm -rf tmp3

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/config_manager
    chmod -R 777 /home/user
