#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct

records = [
    (1690000000, 0x0A000001, b"AUTH_NORMAL_TOKEN_123"),
    (1690000005, 0x0A000002, b"A" * 55),
    (1690000010, 0x0A000003, b"\xde\xad\xbe\xef" + b"B" * 124),
    (1690000015, 0x0A000004, b"AUTH_SECRET_XYZ")
]

with open("/home/user/traffic_log.bin", "wb") as f:
    for ts, ip, token in records:
        f.write(struct.pack("<I I H", ts, ip, len(token)))
        f.write(token)

with open("/home/user/auth_crashes.log", "w") as f:
    f.write("[INFO] Service started at 1690000000\n")
    f.write("[WARN] Invalid login attempt\n")
    f.write("[FATAL] Crash detected at timestamp 1690000010\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
