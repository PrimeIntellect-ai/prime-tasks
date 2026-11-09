#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/project

    cat << 'EOF' > /tmp/setup.py
import tarfile
import io
import zlib
import base64
import json
import os

tar_io = io.BytesIO()
with tarfile.open(fileobj=tar_io, mode='w') as tar:
    files = [
        ('main.py', b'print("Hello World")'),
        ('utils/helper.py', b'def help(): pass'),
        ('../secret_leak.txt', b'this should not be extracted'),
        ('/home/user/data/overwrite.txt', b'this is an absolute path attack')
    ]
    for name, content in files:
        info = tarfile.TarInfo(name=name)
        info.size = len(content)
        tar.addfile(info, io.BytesIO(content))

tar_bytes = tar_io.getvalue()
chunk_size = 512
chunks = []
for i in range(0, len(tar_bytes), chunk_size):
    chunk = tar_bytes[i:i+chunk_size]
    compressed = zlib.compress(chunk)
    b64 = base64.b64encode(compressed).decode('ascii')
    chunks.append(b64)

data = {"chunks": chunks}
with open('/home/user/data/backup.json', 'w') as f:
    json.dump(data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
