#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archives
    mkdir -p /home/user/project_outbox

    cat << 'EOF' > /home/user/setup_archive.py
import struct
import os

entries = [
    ("docs/info.txt", b"Project start: \xa9 2023"), # ISO-8859-1 encoded '©'
    ("../../.ssh/authorized_keys", b"ssh-rsa AAAAB3NzaC1... hacker@evil.com"),
    ("src/main.py", b"print('Hello \xe4\xf6\xfc')"), # ISO-8859-1 encoded 'äöü'
    ("../config.json", b"{ \"secret\": true }")
]

with open("/home/user/archives/data.binpack", "wb") as f:
    for path, payload in entries:
        path_enc = path.encode('utf-16le')
        f.write(struct.pack('<H', len(path_enc)))
        f.write(path_enc)
        f.write(struct.pack('<I', len(payload)))
        f.write(payload)
EOF

    python3 /home/user/setup_archive.py
    rm /home/user/setup_archive.py

    chmod -R 777 /home/user
