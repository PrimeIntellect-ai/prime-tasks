#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import tarfile
import os
import io

os.makedirs("/home/user", exist_ok=True)

with open("/tmp/safe1.bin", "wb") as f:
    f.write(b"\xDE\xAD\xBE\xEF" + b"some dataset content")
with open("/tmp/safe2.dat", "wb") as f:
    f.write(b"\xCA\xFE\xBA\xBE" + b"more dataset content")
with open("/tmp/safe_alpha.bin", "wb") as f:
    f.write(b"\x12\x34\x56\x78" + b"alpha content")
with open("/tmp/evil.txt", "wb") as f:
    f.write(b"\x00\x00\x00\x00" + b"malicious content")
with open("/tmp/root.bin", "wb") as f:
    f.write(b"\xFF\xFF\xFF\xFF" + b"root content")

with tarfile.open("/home/user/dataset.tar", "w") as tar:
    tar.add("/tmp/safe2.dat", arcname="safe2.dat")
    tar.add("/tmp/safe1.bin", arcname="safe1.bin")
    tar.add("/tmp/safe_alpha.bin", arcname="safe_alpha.bin")

    # Use TarInfo to prevent path normalization/stripping
    info_evil = tarfile.TarInfo("../evil.txt")
    with open("/tmp/evil.txt", "rb") as f:
        content_evil = f.read()
    info_evil.size = len(content_evil)
    tar.addfile(info_evil, io.BytesIO(content_evil))

    info_root = tarfile.TarInfo("/root.bin")
    with open("/tmp/root.bin", "rb") as f:
        content_root = f.read()
    info_root.size = len(content_root)
    tar.addfile(info_root, io.BytesIO(content_root))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
