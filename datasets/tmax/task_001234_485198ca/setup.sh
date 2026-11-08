#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate reference audio
    espeak -w /app/reference.wav "Storage capacity reached"

    # Generate clean and evil tar files using Python
    cat << 'EOF' > /tmp/make_tars.py
import tarfile
import os

with open("/tmp/dummy", "wb") as f:
    f.write(b"data")

# Clean 1-10
for i in range(1, 11):
    with tarfile.open(f"/app/corpus/clean/clean{i}.tar", "w") as tar:
        info = tarfile.TarInfo(f"clean{i}.txt")
        info.size = 4
        with open("/tmp/dummy", "rb") as f:
            tar.addfile(info, f)

# Evil 1-4: ../
for i in range(1, 5):
    with tarfile.open(f"/app/corpus/evil/evil{i}.tar", "w") as tar:
        info = tarfile.TarInfo(f"../evil{i}.txt")
        info.size = 4
        with open("/tmp/dummy", "rb") as f:
            tar.addfile(info, f)

# Evil 5-7: absolute paths
for i in range(5, 8):
    with tarfile.open(f"/app/corpus/evil/evil{i}.tar", "w") as tar:
        info = tarfile.TarInfo(f"/etc/evil{i}.txt")
        info.size = 4
        with open("/tmp/dummy", "rb") as f:
            tar.addfile(info, f)

# Evil 8-10: symlinks
for i in range(8, 11):
    with tarfile.open(f"/app/corpus/evil/evil{i}.tar", "w") as tar:
        info = tarfile.TarInfo(f"symlink{i}")
        info.type = tarfile.SYMTYPE
        info.linkname = "/etc/passwd"
        tar.addfile(info)
EOF
    python3 /tmp/make_tars.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
