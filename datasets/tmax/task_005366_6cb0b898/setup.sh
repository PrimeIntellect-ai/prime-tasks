#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/increments
    mkdir -p /home/user/restore
    mkdir -p /home/user/tmp_base

    # 1. Create base files
    echo -n "Base data A" > /home/user/tmp_base/file1.txt
    head -c 100 /dev/zero | tr '\0' '\1' > /home/user/tmp_base/file2.bin
    echo "To be deleted" > /home/user/tmp_base/file3.txt

    # 2. Tar them up
    cd /home/user/tmp_base
    tar -czf /home/user/backups/base.tar.gz *
    cd /home/user

    # 3. Split tarball and build raw_dump.dat
    python3 -c '
import os

with open("/home/user/backups/base.tar.gz", "rb") as f:
    tar_data = f.read()

chunk_size = len(tar_data) // 3
chunks = [tar_data[0:chunk_size], tar_data[chunk_size:chunk_size*2], tar_data[chunk_size*2:]]

with open("/home/user/backups/raw_dump.dat", "wb") as out:
    out.write(b"SYSTEM LOG START\nSome random log line 1\nLine 2\n")

    for i, c in enumerate(chunks):
        out.write(f"[CHUNK_START:{len(c)}]\n".encode())
        out.write(c)
        out.write(b"\n[CHUNK_END]\n")
        out.write(b"INTERLEAVED LOG TEXT\nMore logs...\n")
'

    # 4. Create differential increments
    echo -n "Appended data A" > /home/user/backups/increments/text.txt
    head -c 50 /dev/zero | tr '\0' '\2' > /home/user/backups/increments/app.bin

    # 5. Create differential log
    cat << 'EOF' > /home/user/backups/differential.log
OPERATION: DELETE
TARGET: file3.txt
---
OPERATION: APPEND
TARGET: file2.bin
SOURCE: /home/user/backups/increments/app.bin
---
OPERATION: APPEND
TARGET: file1.txt
SOURCE: /home/user/backups/increments/text.txt
---
EOF

    # Clean up tmp
    rm -rf /home/user/tmp_base
    rm -f /home/user/backups/base.tar.gz

    chmod -R 777 /home/user
