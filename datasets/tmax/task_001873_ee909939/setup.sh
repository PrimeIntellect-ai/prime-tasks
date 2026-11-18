#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/extracted_docs
    mkdir -p /home/user/setup
    cat << 'EOF' > /home/user/setup/create_archive.py
import struct

entries = [
    # (path, data)
    (b"intro.md", b"Welcome to the system."),
    (b"../../../home/user/.ssh/id_rsa.txt", b"fake_key_data_123"),
    (b"/absolute/path/to/Important_Notice.MD", b"System maintenance on Friday."),
    (b"nested/dir/CONFIG.json", b'{"status": "ok"}')
]

with open("/home/user/legacy_docs.bin", "wb") as f:
    for path, data in entries:
        f.write(struct.pack("<H", len(path)))
        f.write(path)
        f.write(struct.pack("<I", len(data)))
        f.write(data)
EOF
    python3 /home/user/setup/create_archive.py
    rm -rf /home/user/setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
