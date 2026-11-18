#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed findutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

random.seed(42)

repo_dir = "/home/user/artifact_repo"
os.makedirs(repo_dir, exist_ok=True)

artifacts = [
    {"id": "bin-alpha-01", "version": "1.0.0", "size": 1048576, "path": "x86_64/core", "bad": True},
    {"id": "bin-beta-99", "version": "2.1.4-rc1", "size": 512000, "path": "arm64/core", "bad": False},
    {"id": "lib-gamma-zz", "version": "0.9.9", "size": 2048, "path": "noarch/libs/extra", "bad": True},
    {"id": "pkg-delta-42", "version": "4.2.0", "size": 9999999, "path": "x86_64/apps", "bad": False},
    {"id": "bin-epsilon", "version": "1.0.1", "size": 1048576, "path": "x86_64/core", "bad": True},
]

for art in artifacts:
    art_dir = os.path.join(repo_dir, art["path"])
    os.makedirs(art_dir, exist_ok=True)

    file_path = os.path.join(art_dir, f"{art['id']}.info")

    lines = [
        f"{random.choice(['ID', 'Id', 'id'])}: {art['id']}",
        f"{random.choice(['Version', 'VER', 'version'])}: {art['version']}",
        f"{random.choice(['Size', 'SIZE', 'size'])}: {art['size']}"
    ]
    random.shuffle(lines)

    content = "\n".join(lines) + "\n"
    if art["bad"]:
        content = content.replace("\n", "\r\n")
        content_bytes = bytearray(content.encode('utf-8'))
        for _ in range(5):
            idx = random.randint(0, len(content_bytes) - 1)
            content_bytes.insert(idx, 0x00)
    else:
        content_bytes = content.encode('utf-8')

    with open(file_path, "wb") as f:
        f.write(content_bytes)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
