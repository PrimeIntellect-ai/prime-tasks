#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/backup_source/level1/level2

    # Use python to write exact binary bytes to avoid printf shell escaping issues
    python3 -c '
import os
with open("/home/user/backup_source/valid1.bin", "wb") as f:
    f.write(b"BKP\x01\x11\x22\x33\x44")
with open("/home/user/backup_source/level1/level2/valid2.bin", "wb") as f:
    f.write(b"BKP\x01\xAA\xBB\xCC\xDD")
with open("/home/user/backup_source/invalid1.bin", "wb") as f:
    f.write(b"BKP\x02\x11\x22")
with open("/home/user/backup_source/level1/invalid2.txt", "w") as f:
    f.write("just some text\n")
'

    # Create symlink loops
    ln -s /home/user/backup_source /home/user/backup_source/level1/loop_to_root
    ln -s /home/user/backup_source/level1/level2 /home/user/backup_source/level1/level2/loop_to_self

    # Fix permissions
    chown -R user:user /home/user/backup_source
    chmod -R 777 /home/user
