#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services
    mkdir -p /home/user/data/auth
    mkdir -p /home/user/data/data
    mkdir -p /home/user/data/web
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/services/auth.py
import time
while True:
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/services/data.py
import time
while True:
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/services/web.py
import time
while True:
    time.sleep(1)
EOF

    chmod +x /home/user/services/*.py
    chmod -R 777 /home/user
