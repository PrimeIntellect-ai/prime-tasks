#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_state.py
import os
import struct

os.makedirs('/home/user/configs', exist_ok=True)

with open('/home/user/configs/app.conf', 'w') as f:
    f.write("port=8080\nhost=localhost\n")

with open('/home/user/configs/db.conf', 'w') as f:
    f.write("user=root\npass=secret\n")

with open('/home/user/configs/network.conf', 'w') as f:
    f.write("timeout=30\n")

records = [
    (b"app.conf", 50),
    (b"db.conf", 128),
    (b"legacy.conf", 200)
]

with open("/home/user/state.bin", "wb") as f:
    for name, checksum in records:
        f.write(struct.pack("63sB", name, checksum))
EOF

    python3 /home/user/setup_state.py
    rm /home/user/setup_state.py

    chmod -R 777 /home/user
