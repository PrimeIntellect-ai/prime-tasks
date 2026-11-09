#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services/db
    mkdir -p /home/user/services/auth
    mkdir -p /home/user/services/api
    mkdir -p /home/user/services/web

    cat << 'EOF' > /home/user/services/db/service.conf
# Database config
LISTEN_PORT=8080
TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/services/auth/service.conf
# Auth config
LISTEN_PORT=8081
UPSTREAM_URL=http://localhost:8080
LOG_LEVEL=debug
EOF

    cat << 'EOF' > /home/user/services/api/service.conf
# API config
LISTEN_PORT=8082
UPSTREAM_URL=http://localhost:8081
EOF

    cat << 'EOF' > /home/user/services/web/service.conf
# Web config
LISTEN_PORT=8083
UPSTREAM_URL=http://localhost:8082
THEME=dark
EOF

    chmod -R 777 /home/user
