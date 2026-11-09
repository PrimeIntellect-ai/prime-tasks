#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_logs/backend
    mkdir -p /home/user/project_logs/frontend/components
    mkdir -p /home/user/project_logs/auth

    cat << 'EOF' > /tmp/gen_clog.py
import sys
import struct

def rle_compress(text):
    if not text: return b''
    compressed = bytearray()
    i = 0
    while i < len(text):
        char = text[i]
        count = 1
        while i + 1 < len(text) and text[i+1] == char and count < 255:
            count += 1
            i += 1
        compressed.extend(struct.pack('BB', count, char))
        i += 1
    return compressed

logs = {
    "backend/db.clog": b"[2023-10-01 10:00:00] INFO: DB connected\n[2023-10-01 10:01:05] ERROR: Connection timeout\nRetrying in 5 seconds...\nStack trace:\n  at db.connect (db.js:42)\n[2023-10-01 10:01:10] INFO: DB reconnected\n",
    "frontend/components/ui.clog": b"[2023-10-01 09:15:00] DEBUG: Rendered button\n[2023-10-01 09:16:00] ERROR: Null pointer exception in UI\n  Component: Header\n  Props: undefined\n",
    "auth/login.clog": b"[2023-10-01 08:00:00] WARN: Invalid password attempt\n[2023-10-01 08:05:00] INFO: User login success\n"
}

for path, content in logs.items():
    full_path = "/home/user/project_logs/" + path
    with open(full_path, "wb") as f:
        f.write(rle_compress(content))
EOF

    python3 /tmp/gen_clog.py
    rm /tmp/gen_clog.py

    chmod -R 777 /home/user
