#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/backups/server_alpha/db
    mkdir -p /home/user/backups/server_alpha/web/archived

    # Plain log
    cat << 'EOF' > /home/user/backups/server_alpha/db/sync.log
Starting sync
Connecting to DB
Querying records
Records: 1042
Sync complete
Connection closed
EOF

    # Plain bin
    echo -n "dummy_binary_data_123" > /home/user/backups/server_alpha/db/state.bin

    # Setup for tar.gz
    mkdir -p /tmp/tar_setup
    cat << 'EOF' > /tmp/tar_setup/access.log
GET /index.html 200
GET /style.css 200
GET /app.js 200
POST /api/login 401
POST /api/login 200
EOF
    echo -n "compressed_binary_data_456" > /tmp/tar_setup/core.bin
    cd /tmp/tar_setup && tar -czf /home/user/backups/server_alpha/web/archived/old_logs.tar.gz access.log core.bin

    # Setup for zip
    mkdir -p /tmp/zip_setup/nested
    cat << 'EOF' > /tmp/zip_setup/nested/error.log
Warning: High memory usage
Error: Timeout on port 8080
Fatal: Process crashed
EOF
    cd /tmp/zip_setup && zip -r /home/user/backups/server_alpha/app_backup.zip nested/error.log

    # Cleanup
    rm -rf /tmp/tar_setup /tmp/zip_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
