#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_caz.py
import struct
import os

files = [
    (b"README.md", b"Project info here."),
    (b"src/main.c", b"int main() { return 0; }"),
    (b"../../../home/user/hacked.txt", b"You have been zip slipped!"),
    (b"/etc/shadow", b"root:x:0:0:root:/root:/bin/bash"),
    (b"docs/../secret.txt", b"Should be rejected based on rules.")
]

with open("/home/user/project.caz", "wb") as f:
    f.write(b"CAZ1")
    f.write(struct.pack("<I", len(files)))
    for path, data in files:
        f.write(struct.pack("<H", len(path)))
        f.write(path)
        f.write(struct.pack("<I", len(data)))
        f.write(data)
EOF

    python3 /tmp/gen_caz.py
    rm /tmp/gen_caz.py

    chmod -R 777 /home/user
