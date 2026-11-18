#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Additional system packages
    apt-get install -y tar gzip coreutils

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/server_configs/app1
    mkdir -p /home/user/server_configs/app2/nested
    mkdir -p /home/user/server_configs/app3

    # App 1
    cat << 'EOF' > /home/user/server_configs/app1/settings.conf
PORT=8080
HOST=localhost
SECRET_KEY=f92kd0293nf
DEBUG=true
EOF

    cat << 'EOF' > /home/user/server_configs/app1/readme.txt
This is a readme, do not include in backup.
SECRET_KEY=should_not_be_redacted_or_archived
EOF

    # App 2
    cat << 'EOF' > /home/user/server_configs/app2/nested/db.conf
DB_USER=admin
DB_PASS=password123
SECRET_KEY=XyZ992Mka
TIMEOUT=30
EOF

    # App 3
    cat << 'EOF' > /home/user/server_configs/app3/cache.conf
MAX_MEMORY=512M
SECRET_KEY=12345abcd
EVICTION_POLICY=LRU
EOF

    # Set permissions
    chmod -R 777 /home/user
