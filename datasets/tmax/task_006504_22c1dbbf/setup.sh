#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile

os.makedirs("/home/user/incoming", exist_ok=True)
os.makedirs("/home/user/base_docs", exist_ok=True)

# 1. Create Base Docs
base_files = {
    "intro.md": "# Introduction\nWelcome to NexusOS.\n",
    "setup.md": "# Setup\nRun the installer.\n"
}

for fname, content in base_files.items():
    with open(f"/home/user/base_docs/{fname}", "w") as f:
        f.write(content)

with tarfile.open("/home/user/base_docs.tar.gz", "w:gz") as tar:
    for fname in base_files.keys():
        tar.add(f"/home/user/base_docs/{fname}", arcname=fname)

# 2. Create Incoming Docpacks
incoming_docs = {
    "intro.md": "<<header1>>Introduction<</header1>>\nWelcome to ProjectAlpha.\n",
    "setup.md": "<<header1>>Setup<</header1>>\nRun the installer and reboot.\n",
    "advanced.md": "<<header1>>Advanced<</header1>>\nConfigure the NexusOS kernel.\n"
}

for fname, content in incoming_docs.items():
    content_bytes = content.encode('utf-8')
    size = len(content_bytes)

    magic = b"DOCP"
    size_bytes = struct.pack("<I", size)
    fname_bytes = fname.encode('utf-8').ljust(32, b'\x00')

    name_part = fname.split('.')[0]
    with open(f"/home/user/incoming/{name_part}.docpack", "wb") as f:
        f.write(magic + size_bytes + fname_bytes + content_bytes)
EOF

    python3 /tmp/setup.py
    rm -rf /home/user/base_docs /tmp/setup.py

    chmod -R 777 /home/user
