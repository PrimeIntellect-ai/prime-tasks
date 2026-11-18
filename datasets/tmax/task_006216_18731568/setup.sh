#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/worker.py
#!/usr/bin/env python3
import time
while True:
    time.sleep(1)
EOF
    chmod +x /home/user/worker.py

    chmod -R 777 /home/user
