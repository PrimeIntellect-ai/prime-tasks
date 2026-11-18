#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate dummy video
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/security_cam.mp4

    # Generate backup_root.tar.gz
    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import gzip

os.makedirs("/tmp/backup_root/dirA/dirB", exist_ok=True)
os.makedirs("/tmp/backup_root/dirC", exist_ok=True)

# Create infinite loops
os.symlink("../dirA", "/tmp/backup_root/dirA/dirB/loop_back")
os.symlink("../../dirC", "/tmp/backup_root/dirA/loop_C")
os.symlink("../dirA", "/tmp/backup_root/dirC/loop_A")

timestamps = [2.5, 7.1, 12.0, 15.3, 22.8]
chunks = [
    ("chunk_1.bin.gz", [2.5, 7.1]),
    ("chunk_2.bin.gz", [12.0]),
    ("chunk_3.bin.gz", [15.3, 22.8])
]

# Distribute chunks
paths = [
    "/tmp/backup_root/chunk_2.bin.gz",
    "/tmp/backup_root/dirA/chunk_1.bin.gz",
    "/tmp/backup_root/dirC/chunk_3.bin.gz"
]

for path, (name, times) in zip(paths, chunks):
    with gzip.open(path, 'wt') as f:
        for t in times:
            f.write(f"{t}\n")

with tarfile.open("/app/backup_root.tar.gz", "w:gz") as tar:
    tar.add("/tmp/backup_root", arcname="backup_root")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/backup_root

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
