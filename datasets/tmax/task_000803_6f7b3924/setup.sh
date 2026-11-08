#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/incoming_artifacts/subdir
    mkdir -p /home/user/repo/chunks

    cat << 'EOF' > /tmp/setup.py
import os
import random

random.seed(42)

def create_file(path, is_elf, size):
    with open(path, 'wb') as f:
        if is_elf:
            f.write(b'\x7FELF')
            f.write(os.urandom(int(size - 4)))
        else:
            f.write(b'MZ\x90\x00')
            f.write(os.urandom(int(size - 4)))

create_file('/home/user/incoming_artifacts/file1.bin', True, 1024 * 1024 * 1.5)
create_file('/home/user/incoming_artifacts/file2.txt', False, 5000)
create_file('/home/user/incoming_artifacts/subdir/file3.exe', True, 1024 * 600)
create_file('/home/user/incoming_artifacts/subdir/file4.dat', False, 1024 * 1024)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
