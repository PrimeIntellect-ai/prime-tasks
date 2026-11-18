#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/configs
    mkdir -p /home/user/last_backup

    cat << 'EOF' > /home/user/last_backup/app.ini
[DEFAULT]
EXPORT_APP_PORT=8080
INTERNAL_DEBUG=true
EOF

    cat << 'EOF' > /home/user/last_backup/db.ini
[DATABASE]
EXPORT_DB_HOST=localhost
EXPORT_DB_PORT=5432
CONNECTION_TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/configs/app.ini
[DEFAULT]
EXPORT_APP_PORT=8081
INTERNAL_DEBUG=false
EXPORT_APP_MODE=production
EOF

    cp /home/user/last_backup/db.ini /home/user/configs/db.ini

    cat << 'EOF' > /home/user/configs/cache.ini
[CACHE]
EXPORT_CACHE_TTL=3600
MEMORY_LIMIT=512M
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
