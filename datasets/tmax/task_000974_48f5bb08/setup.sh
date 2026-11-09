#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user', exist_ok=True)

def write_file_entry(f, path, content):
    path_bytes = path.encode('ascii')
    if len(path_bytes) < 100:
        path_bytes += b'\0' * (100 - len(path_bytes))
    size = len(content)
    size_bytes = struct.pack('<Q', size)
    reserved = b'\0' * 20

    header = path_bytes + size_bytes + reserved
    f.write(header)
    f.write(content.encode('utf-8'))

with open('/home/user/backup.bin', 'wb') as f:
    write_file_entry(f, 'index.md', '# Index\nWelcome to docs.')
    write_file_entry(f, 'api/v1.md', '# API v1\nSpecs here.')
    write_file_entry(f, 'shared/styles.css', 'body { color: black; }')
    # Loop begins
    write_file_entry(f, 'shared/shared/styles.css', 'body { color: black; }')
    write_file_entry(f, 'shared/shared/shared/styles.css', 'body { color: black; }')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
