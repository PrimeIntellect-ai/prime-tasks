#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/logs
    mkdir -p /home/user/service_app

    # Create log files
    cat << 'EOF' > /home/user/logs/api.log
[2023-11-05T14:20:01Z] INFO HTTP GET /health 200
[2023-11-05T14:21:15Z] INFO HTTP POST /login 200
[2023-11-05T14:22:05Z] ERROR HTTP POST /data 500
[2023-11-05T14:22:15Z] ERROR HTTP GET /users 500
EOF

    cat << 'EOF' > /home/user/logs/db.log
[2023-11-05T14:20:00Z] INFO Connection established from 10.0.0.5
[2023-11-05T14:21:14Z] INFO Query OK
[2023-11-05T14:22:04Z] FATAL: password authentication failed for user 'dbadmin'
[2023-11-05T14:22:14Z] FATAL: password authentication failed for user 'dbadmin'
[2023-11-05T14:23:01Z] FATAL: password authentication failed for user 'dbadmin'
EOF

    # Setup git repository
    cd /home/user/service_app
    git init
    git config user.email "sre@example.com"
    git config user.name "SRE"

    cat << 'EOF' > settings.py
DB_HOST = "db.internal"
DB_USER = "dbadmin"
DB_PASS = "Tr0ub4dor&3"
EOF
    git add settings.py
    git commit -m "Initial commit with working DB config"

    cat << 'EOF' > settings.py
DB_HOST = "db.internal"
DB_USER = "dbadmin"
DB_PASS = "hunter2_bad_password"
EOF
    git add settings.py
    git commit -m "Update settings for new environment"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
