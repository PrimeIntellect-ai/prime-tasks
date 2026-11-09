#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_repo
    cd /home/user/server_repo
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"
    echo '{"db_pass": "p4ssw0rd_123_!$"}' > db_config.json
    git add db_config.json
    git commit -m "Add initial configuration"

    echo '{"db_pass": "REDACTED"}' > db_config.json
    git add db_config.json
    git commit -m "Redact database password for security"

    cd /home/user
    cat << 'EOF' > crash_trace.log
INFO: Server starting up...
INFO: Initializing thread pool (4 threads)
DEBUG: Thread 1: Listening on port 8080
DEBUG: Thread 2: Blocked on mutex lock
DEBUG: Thread 3: Processing incoming connection from 10.0.0.42
ERROR: Thread 3: Segfault at address 0x7ffd5e3a9b20
INFO: Thread 4: Exiting cleanly
FATAL: Server crashed due to unhandled signal.
EOF

    chmod -R 777 /home/user
