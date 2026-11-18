#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create dummy files and archive
    mkdir -p /home/user/source_app
    echo "SECRET_KEY=12345" > /home/user/source_app/.env
    echo -e "DATA OK\nCORRUPT block 1\nDATA OK\nDATA OK\nCORRUPT block 2\nERROR missing\nCORRUPT block 3" > /home/user/source_app/restore_data.log

    cat << 'EOF' > /home/user/source_app/server.py
import time
print("Server starting...")
time.sleep(2)
# Simulating a crash
exit(1)
EOF

    cd /home/user/source_app && tar -czf /home/user/backup.tar.gz .env restore_data.log server.py
    cd /
    rm -rf /home/user/source_app

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
