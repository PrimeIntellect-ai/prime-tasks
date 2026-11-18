#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import tarfile
import os
import io

os.makedirs("/home/user", exist_ok=True)

with tarfile.open("/home/user/config_backup.tar", "w") as tar:
    # Safe 1
    info = tarfile.TarInfo(name="service/app.conf")
    info.mtime = 1600000000
    content = b"port=8080"
    info.size = len(content)
    tar.addfile(info, io.BytesIO(content))

    # Safe 2
    info = tarfile.TarInfo(name="service/db.conf")
    info.mtime = 1650000000
    content = b"db=prod"
    info.size = len(content)
    tar.addfile(info, io.BytesIO(content))

    # Malicious 1 (Newer mtime, should be skipped)
    info = tarfile.TarInfo(name="../evil.sh")
    info.mtime = 1660000000
    content = b"echo pwned"
    info.size = len(content)
    tar.addfile(info, io.BytesIO(content))

    # Malicious 2
    info = tarfile.TarInfo(name="/etc/fake_shadow")
    info.mtime = 1660000000
    content = b"root:x:0:0:"
    info.size = len(content)
    tar.addfile(info, io.BytesIO(content))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
