#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar bzip2
    pip3 install pytest

    mkdir -p /home/user/configs_old_raw
    mkdir -p /home/user/configs_current

    cat << 'EOF' > /home/user/configs_old_raw/web.conf
# Web Config
DEBUG_LEVEL=1
SERVER_PORT=8080
WORKERS=4
EOF

    cat << 'EOF' > /home/user/configs_old_raw/db.conf
# DB Config
DEBUG_LEVEL=0
SERVER_PORT=5432
MAX_CONN=100
EOF

    cat << 'EOF' > /home/user/configs_old_raw/cache.conf
# Cache Config
DEBUG_LEVEL=0
SERVER_PORT=6379
MEMORY=2G
EOF

    cat << 'EOF' > /home/user/configs_old_raw/app.conf
# App Config
DEBUG_LEVEL=1
SERVER_PORT=8080
MODULES=auth,payment
EOF

    cd /home/user/configs_old_raw && tar -czf /home/user/configs_old.tar.gz *
    cd /
    rm -rf /home/user/configs_old_raw

    cat << 'EOF' > /home/user/configs_current/db.conf
# DB Config
DEBUG_LEVEL=0
SERVER_PORT=5432
MAX_CONN=100
EOF

    cat << 'EOF' > /home/user/configs_current/cache.conf
# Cache Config
DEBUG_LEVEL=0
SERVER_PORT=6379
MEMORY=2G
EOF

    cat << 'EOF' > /home/user/configs_current/web.conf
# Web Config
DEBUG_LEVEL=1
SERVER_PORT=8080
WORKERS=8
EOF

    cat << 'EOF' > /home/user/configs_current/app.conf
# App Config
DEBUG_LEVEL=1
SERVER_PORT=8080
MODULES=auth,payment,shipping
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
