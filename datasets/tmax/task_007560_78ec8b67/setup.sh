#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/db_dumps', exist_ok=True)

# Phase 1 Setup: Create duplicates
base_contents = [os.urandom(1024) for _ in range(5)]
for i in range(1, 51):
    content = random.choice(base_contents)
    with open(f'/home/user/db_dumps/dump_{i}.sql', 'wb') as f:
        f.write(content)

# Phase 2 Setup: Create massive_log.bin
data = b''
for _ in range(1000):
    data += b'\x00' * random.randint(10, 100)
    data += os.urandom(5)

with open('/home/user/massive_log.bin', 'wb') as f:
    f.write(data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
