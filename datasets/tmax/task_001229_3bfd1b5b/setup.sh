#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron psmisc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services
    mkdir -p /home/user/run

    cat << 'EOF' > /home/user/services/alpha.py
import time
while True:
    time.sleep(60)
EOF

    cat << 'EOF' > /home/user/services/beta.py
import time
while True:
    time.sleep(60)
EOF

    chmod +x /home/user/services/*.py

    chmod -R 777 /home/user
