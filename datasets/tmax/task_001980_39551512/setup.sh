#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os

os.makedirs('/home/user', exist_ok=True)
archive_path = '/home/user/legacy_archive.bin'

records = [
    (1, b"Random binary data 12345"),
    (2, b"ID:1001|DATE:20231015|STATUS:A"),
    (1, b"More binary stuff"),
    (2, b"ID:1002|DATE:20231016|STATUS:B"),
    (2, b"ID:1003|DATE:20231017|STATUS:C"),
]

with open(archive_path, 'wb') as f:
    for r_type, payload in records:
        magic = 0xBACCBACC
        length = len(payload)
        header = struct.pack('<III', magic, r_type, length)
        f.write(header + payload)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
